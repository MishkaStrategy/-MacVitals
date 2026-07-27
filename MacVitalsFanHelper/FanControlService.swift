import Foundation
import Security

final class FanControlService: NSObject, NSXPCListenerDelegate, FanControlXPCProtocol,
  @unchecked Sendable
{
  private let listener = NSXPCListener(machServiceName: FanControlServiceConstants.machServiceName)
  private let queue = DispatchQueue(label: "com.mishkacher.MacVitals.FanControl.service")
  private var connection: AppleSMCConnection?
  private var leases: [Int: Date] = [:]
  private var modeKeyFormats: [Int: String] = [:]
  private var timer: DispatchSourceTimer?

  override init() {
    super.init()
    listener.delegate = self
    startWatchdog()
  }

  func run() {
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
    newConnection.invalidationHandler = { [weak self] in
      self?.queue.async { self?.restoreAllAutomatic() }
    }
    newConnection.interruptionHandler = { [weak self] in
      self?.queue.async { self?.restoreAllAutomatic() }
    }
    newConnection.resume()
    return true
  }

  func status(reply: @escaping (Bool, String?) -> Void) {
    queue.async {
      do {
        let count = try self.fanCount()
        reply(count > 0, count > 0 ? nil : "AppleSMC exposes no fans")
      } catch {
        reply(false, error.localizedDescription)
      }
    }
  }

  func setFanBoost(
    index: Int,
    requestedRPM: Double,
    leaseSeconds: Double,
    reply: @escaping (Bool, Double, String?) -> Void
  ) {
    queue.async {
      do {
        let fan = try self.reading(index: index)
        let plan = try FanControlSafetyPolicy.plan(
          fan: fan,
          requestedRPM: requestedRPM,
          leaseSeconds: leaseSeconds,
          thermalSeverity: FanThermalSeverity(ProcessInfo.processInfo.thermalState))
        try self.enableManualMode(index: index)
        try self.writeTargetRPM(index: index, rpm: plan.targetRPM)
        self.leases[index] = Date().addingTimeInterval(plan.leaseSeconds)
        reply(true, plan.targetRPM, nil)
      } catch {
        self.restoreAutomatic(index: index)
        reply(false, 0, error.localizedDescription)
      }
    }
  }

  func setFanAutomatic(index: Int, reply: @escaping (Bool, String?) -> Void) {
    queue.async {
      do {
        try self.restoreAutomaticThrowing(index: index)
        reply(true, nil)
      } catch {
        reply(false, error.localizedDescription)
      }
    }
  }

  func setAllFansAutomatic(reply: @escaping (Bool, String?) -> Void) {
    queue.async {
      do {
        try self.restoreAllAutomaticThrowing()
        reply(true, nil)
      } catch {
        reply(false, error.localizedDescription)
      }
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
    guard index >= 0, index < try fanCount() else { throw FanControlSafetyError.invalidFan }
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
      let raw = try? connection?.readKey(key),
      let byte = raw?.bytes.first
    else { return .unknown }
    return byte == 0 ? .automatic : .manual
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
    guard index >= 0, index < try fanCount() else { throw FanControlSafetyError.invalidFan }
    let key = try modeKey(index: index)
    try source.writeKey(key, bytes: [0])
    leases.removeValue(forKey: index)
    if leases.isEmpty, (try? source.readKey("Ftst")) != nil {
      try? source.writeKey("Ftst", bytes: [0])
    }
  }

  private func restoreAllAutomatic() {
    try? restoreAllAutomaticThrowing()
  }

  private func restoreAllAutomaticThrowing() throws {
    let count = try fanCount()
    var firstError: Error?
    for index in 0..<count {
      do {
        let key = try modeKey(index: index)
        try smc().writeKey(key, bytes: [0])
      } catch {
        firstError = firstError ?? error
      }
    }
    leases.removeAll()
    if (try? smc().readKey("Ftst")) != nil {
      try? smc().writeKey("Ftst", bytes: [0])
    }
    if let firstError { throw firstError }
  }

  private func startWatchdog() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 5, repeating: 5)
    timer.setEventHandler { [weak self] in self?.watchdogTick() }
    timer.resume()
    self.timer = timer
  }

  private func watchdogTick(now: Date = Date()) {
    let expired = leases.filter { $0.value <= now }.map(\.key)
    for index in expired { restoreAutomatic(index: index) }

    let severity = FanThermalSeverity(ProcessInfo.processInfo.thermalState)
    guard severity == .serious || severity == .critical else { return }
    for index in leases.keys {
      guard let fan = try? reading(index: index), let maximum = fan.maximumRPM else { continue }
      try? writeTargetRPM(index: index, rpm: maximum)
    }
  }
}

nonisolated enum FanControlPeerValidator {
  static func isAuthorizedMainApplication(pid: pid_t) -> Bool {
    guard pid > 0,
      let expectedTeam = ownTeamIdentifier(),
      let information = signingInformation(pid: pid),
      information.identifier == "com.mishkacher.MacVitals",
      information.teamIdentifier == expectedTeam
    else { return false }
    return true
  }

  private static func ownTeamIdentifier() -> String? {
    guard let task = SecTaskCreateFromSelf(nil),
      let value = SecTaskCopyValueForEntitlement(
        task,
        "com.apple.developer.team-identifier" as CFString,
        nil)
    else { return nil }
    return value as? String
  }

  private static func signingInformation(pid: pid_t) -> (identifier: String, teamIdentifier: String)? {
    let attributes = [kSecGuestAttributePid as String: pid] as CFDictionary
    var code: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
      let code
    else { return nil }
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
      let values = information as? [String: Any],
      let identifier = values[kSecCodeInfoIdentifier as String] as? String,
      let team = values[kSecCodeInfoTeamIdentifier as String] as? String
    else { return nil }
    return (identifier, team)
  }
}
