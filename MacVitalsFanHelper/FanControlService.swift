import Foundation

final class FanControlService: NSObject, NSXPCListenerDelegate, FanControlXPCProtocol,
  @unchecked Sendable
{
  private let listener = NSXPCListener(machServiceName: FanControlServiceConstants.machServiceName)
  private let queue = DispatchQueue(label: "com.mishkacher.MacVitals.FanControl.service")
  private let recoveryStore = FanControlRecoveryStore()
  private var connection: AppleSMCConnection?
  private var recovery = FanControlRecoveryState()
  private var startupRecoveryRequired = false
  private var startupError: String?
  private var modeKeyFormats: [Int: String] = [:]
  private var timer: DispatchSourceTimer?

  override init() {
    super.init()
    listener.delegate = self
  }

  func run() {
    queue.sync { performStartupRecovery() }
    startWatchdog()
    listener.resume()
    RunLoop.current.run()
  }

  func listener(
    _: NSXPCListener,
    shouldAcceptNewConnection newConnection: NSXPCConnection
  ) -> Bool {
    guard FanControlPeerValidator.isAuthorizedMainApplication(pid: newConnection.processIdentifier)
    else { return false }

    newConnection.exportedInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
    newConnection.exportedObject = self
    let service = self
    newConnection.invalidationHandler = { service.scheduleRestoreAllAutomatic() }
    newConnection.interruptionHandler = { service.scheduleRestoreAllAutomatic() }
    newConnection.resume()
    return true
  }

  func status(reply: @escaping (Bool, String?) -> Void) {
    let result: (Bool, String?) = queue.sync {
      do {
        let count = try fanCount()
        guard count > 0 else { return (false, "AppleSMC exposes no fans") }
        guard !startupRecoveryRequired else {
          return (false, startupError ?? "Automatic fan recovery is pending")
        }
        guard !recovery.hasPendingRecovery(at: Date()) else {
          return (false, "Automatic fan recovery is pending")
        }
        return (true, nil)
      } catch {
        return (false, error.localizedDescription)
      }
    }
    reply(result.0, result.1)
  }

  func setFanBoost(
    index: Int,
    requestedRPM: Double,
    leaseSeconds: Double,
    reply: @escaping (Bool, Double, String?) -> Void
  ) {
    let result: (Bool, Double, String?) = queue.sync {
      do {
        guard !startupRecoveryRequired, !recovery.hasPendingRecovery(at: Date()) else {
          throw FanControlSafetyError.recoveryPending
        }
        let fan = try reading(index: index)
        let plan = try FanControlSafetyPolicy.plan(
          fan: fan,
          requestedRPM: requestedRPM,
          leaseSeconds: leaseSeconds,
          thermalSeverity: FanThermalSeverity(ProcessInfo.processInfo.thermalState))

        try persistRecoveryTransition { state in
          state.beginRecovery(index: index, now: Date())
        }
        do {
          try enableManualMode(index: index)
          try writeTargetRPM(index: index, rpm: plan.targetRPM)
          try persistRecoveryTransition { state in
            state.activate(
              index: index,
              deadline: Date().addingTimeInterval(plan.leaseSeconds))
          }
          return (true, plan.targetRPM, nil)
        } catch {
          let operationError = error
          do {
            try restoreAutomaticThrowing(index: index)
            return (false, 0, operationError.localizedDescription)
          } catch {
            return (
              false,
              0,
              "\(operationError.localizedDescription). Automatic recovery failed and will be retried: \(error.localizedDescription)"
            )
          }
        }
      } catch {
        return (false, 0, error.localizedDescription)
      }
    }
    reply(result.0, result.1, result.2)
  }

  func setFanAutomatic(index: Int, reply: @escaping (Bool, String?) -> Void) {
    let result: (Bool, String?) = queue.sync {
      do {
        try restoreAutomaticThrowing(index: index)
        return (true, nil)
      } catch {
        return (false, error.localizedDescription)
      }
    }
    reply(result.0, result.1)
  }

  func setAllFansAutomatic(reply: @escaping (Bool, String?) -> Void) {
    let result: (Bool, String?) = queue.sync {
      do {
        try restoreAllAutomaticThrowing()
        return (true, nil)
      } catch {
        return (false, error.localizedDescription)
      }
    }
    reply(result.0, result.1)
  }

  private func scheduleRestoreAllAutomatic() {
    queue.async { [service = self] in service.restoreAllAutomatic() }
  }

  private func performStartupRecovery() {
    do {
      recovery = try recoveryStore.load()
      guard !recovery.isEmpty else {
        startupRecoveryRequired = false
        startupError = nil
        return
      }
      startupRecoveryRequired = true
      startupError = "Recovering fan control after helper restart"
      try restoreAllAutomaticThrowing()
      startupRecoveryRequired = false
      startupError = nil
    } catch {
      startupRecoveryRequired = true
      startupError = "Could not load or restore the fan recovery ledger: \(error.localizedDescription)"
      attemptEmergencyRestoreAll()
    }
  }

  private func attemptEmergencyRestoreAll() {
    do {
      let count = try fanCount()
      let source = try smc()
      var firstError: Error?
      for index in 0..<count {
        do {
          let key = try modeKey(index: index)
          try source.writeKey(key, bytes: [0])
        } catch {
          firstError = firstError ?? error
        }
      }
      if (try? source.readKey("Ftst")) != nil {
        do {
          try source.writeKey("Ftst", bytes: [0])
        } catch {
          firstError = firstError ?? error
        }
      }
      if let firstError { throw firstError }
      try recoveryStore.save(FanControlRecoveryState())
      recovery.markAllRestored()
      startupRecoveryRequired = false
      startupError = nil
    } catch {
      startupRecoveryRequired = true
      startupError = "Emergency automatic fan recovery is pending: \(error.localizedDescription)"
    }
  }

  private func persistRecoveryTransition(
    _ update: (inout FanControlRecoveryState) -> Void
  ) throws {
    var next = recovery
    update(&next)
    try recoveryStore.save(next)
    recovery = next
    if !next.hasPendingRecovery(at: Date()) {
      startupRecoveryRequired = false
      startupError = nil
    }
  }

  private func trackSafeRestore(
    _ update: (inout FanControlRecoveryState) -> Void
  ) {
    var next = recovery
    update(&next)
    recovery = next
    do {
      try recoveryStore.save(next)
    } catch {
      startupRecoveryRequired = true
      startupError = "Could not persist automatic fan recovery: \(error.localizedDescription)"
    }
  }

  private func smc() throws -> AppleSMCConnection {
    if let connection { return connection }
    let created = try AppleSMCConnection()
    connection = created
    return created
  }

  private func fanCount() throws -> Int {
    let raw = try smc().readKey("FNum")
    guard let decoded = AppleSMCDataDecoder.unsignedInteger(raw),
      let count = FanValueNormalizer.fanCount(decoded)
    else { throw AppleSMCError.invalidPayload }
    return count
  }

  private func reading(index: Int) throws -> FanReading {
    let count = try fanCount()
    guard index >= 0, index < count else { throw FanControlSafetyError.invalidFan }
    let source = try smc()
    func number(_ key: String) -> Double? {
      guard let value = try? source.readKey(key) else { return nil }
      return AppleSMCDataDecoder.number(value)
    }
    guard let reading = FanValueNormalizer.reading(
      index: index,
      current: number("F\(index)Ac"),
      target: number("F\(index)Tg"),
      minimum: number("F\(index)Mn"),
      maximum: number("F\(index)Mx"),
      mode: readMode(index: index))
    else { throw AppleSMCError.invalidPayload }
    return reading
  }

  private func readMode(index: Int) -> FanMode {
    guard let key = try? modeKey(index: index),
      let source = try? smc(),
      let raw = try? source.readKey(key),
      let byte = raw.bytes.first
    else { return .unknown }
    return FanMode.decodeSMCByte(byte)
  }

  private func modeKey(index: Int) throws -> String {
    if let cached = modeKeyFormats[index] { return String(format: cached, index) }
    let source = try smc()
    for format in ["F%dmd", "F%dMd"] {
      let key = String(format: format, index)
      if (try? source.readKey(key)) != nil {
        modeKeyFormats[index] = format
        return key
      }
    }
    throw AppleSMCError.invalidPayload
  }

  private func enableManualMode(index: Int) throws {
    let source = try smc()
    let key = try modeKey(index: index)
    do {
      try source.writeKey(key, bytes: [1])
      return
    } catch {
      guard (try? source.readKey("Ftst")) != nil else { throw error }
    }

    try source.writeKey("Ftst", bytes: [1])
    Thread.sleep(forTimeInterval: 0.5)
    var lastError: Error = AppleSMCError.invalidPayload
    for _ in 0..<50 {
      do {
        try source.writeKey(key, bytes: [1])
        return
      } catch {
        lastError = error
        Thread.sleep(forTimeInterval: 0.1)
      }
    }
    throw lastError
  }

  private func writeTargetRPM(index: Int, rpm: Double) throws {
    let source = try smc()
    let key = "F\(index)Tg"
    let existing = try source.readKey(key)
    guard let bytes = AppleSMCDataDecoder.bytes(
      for: rpm,
      dataType: existing.dataType,
      size: existing.bytes.count)
    else { throw AppleSMCError.invalidPayload }
    try source.writeKey(key, bytes: bytes)
  }

  private func restoreAutomatic(index: Int) {
    try? restoreAutomaticThrowing(index: index)
  }

  private func restoreAutomaticThrowing(index: Int) throws {
    let source = try smc()
    let count = try fanCount()
    guard index >= 0, index < count else { throw FanControlSafetyError.invalidFan }
    trackSafeRestore { state in
      state.beginRecovery(index: index, now: Date())
    }

    var firstError: Error?
    do {
      let key = try modeKey(index: index)
      try source.writeKey(key, bytes: [0])
    } catch {
      firstError = error
    }

    if !recovery.hasTrackedFan(excluding: index), (try? source.readKey("Ftst")) != nil {
      do {
        try source.writeKey("Ftst", bytes: [0])
      } catch {
        firstError = firstError ?? error
      }
    }

    if let firstError { throw firstError }
    try persistRecoveryTransition { state in
      state.markRestored(index: index)
    }
  }

  private func restoreAllAutomatic() {
    try? restoreAllAutomaticThrowing()
  }

  private func restoreAllAutomaticThrowing() throws {
    let count = try fanCount()
    let source = try smc()
    let recoveryStartedAt = Date()
    trackSafeRestore { state in
      for index in 0..<count {
        state.beginRecovery(index: index, now: recoveryStartedAt)
      }
    }

    var firstError: Error?
    for index in 0..<count {
      do {
        let key = try modeKey(index: index)
        try source.writeKey(key, bytes: [0])
      } catch {
        firstError = firstError ?? error
      }
    }

    if (try? source.readKey("Ftst")) != nil {
      do {
        try source.writeKey("Ftst", bytes: [0])
      } catch {
        firstError = firstError ?? error
      }
    }

    if let firstError { throw firstError }
    try persistRecoveryTransition { state in
      state.markAllRestored()
    }
  }

  private func startWatchdog() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 5, repeating: 5)
    timer.setEventHandler { [service = self] in service.watchdogTick() }
    timer.resume()
    self.timer = timer
  }

  private func watchdogTick(now: Date = Date()) {
    if startupRecoveryRequired {
      attemptEmergencyRestoreAll()
      if startupRecoveryRequired { return }
    }

    for index in recovery.expired(at: now) { restoreAutomatic(index: index) }

    let severity = FanThermalSeverity(ProcessInfo.processInfo.thermalState)
    guard severity == .serious || severity == .critical else { return }
    for index in recovery.indexes {
      guard let fan = try? reading(index: index), let maximum = fan.maximumRPM else { continue }
      try? writeTargetRPM(index: index, rpm: maximum)
    }
  }
}

nonisolated enum FanControlPeerValidator {
  static func isAuthorizedMainApplication(pid: pid_t) -> Bool {
    guard let helperFacts = FanControlCodeSigning.currentFacts(),
      FanControlSigningPolicy.accepts(
        helperFacts,
        expectedIdentifier: FanControlSigningPolicy.helperIdentifier,
        expectedTeamIdentifier: helperFacts.teamIdentifier),
      let applicationFacts = FanControlCodeSigning.facts(pid: pid),
      FanControlSigningPolicy.accepts(
        applicationFacts,
        expectedIdentifier: FanControlSigningPolicy.mainApplicationIdentifier,
        expectedTeamIdentifier: helperFacts.teamIdentifier)
    else { return false }
    return true
  }
}
