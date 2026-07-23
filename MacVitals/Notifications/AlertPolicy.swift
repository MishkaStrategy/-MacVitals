import Foundation

nonisolated enum AlertKind: String, Codable, CaseIterable, Sendable {
  case insufficientPower
  case highMemory
  case lowBattery
}

nonisolated struct AlertEvent: Equatable, Sendable {
  let kind: AlertKind
  let title: String
  let message: String
}

nonisolated struct AlertPolicyConfiguration: Equatable, Sendable {
  static let defaultMemoryThresholdPercent = 90.0
  static let defaultLowBatteryThresholdPercent = 15.0
  static let defaultPowerConfidenceThreshold = 0.8
  static let defaultCooldown: TimeInterval = 15 * 60

  var memoryThresholdPercent: Double
  var lowBatteryThresholdPercent: Double
  var powerConfidenceThreshold: Double
  var cooldown: TimeInterval

  init(
    memoryThresholdPercent: Double = defaultMemoryThresholdPercent,
    lowBatteryThresholdPercent: Double = defaultLowBatteryThresholdPercent,
    powerConfidenceThreshold: Double = defaultPowerConfidenceThreshold,
    cooldown: TimeInterval = defaultCooldown
  ) {
    self.memoryThresholdPercent = Self.bounded(
      memoryThresholdPercent,
      defaultValue: Self.defaultMemoryThresholdPercent,
      range: 1...100)
    self.lowBatteryThresholdPercent = Self.bounded(
      lowBatteryThresholdPercent,
      defaultValue: Self.defaultLowBatteryThresholdPercent,
      range: 1...100)
    self.powerConfidenceThreshold = Self.bounded(
      powerConfidenceThreshold,
      defaultValue: Self.defaultPowerConfidenceThreshold,
      range: 0...1)
    self.cooldown = Self.bounded(
      cooldown,
      defaultValue: Self.defaultCooldown,
      range: 0...TimeInterval.greatestFiniteMagnitude)
  }

  private static func bounded(
    _ value: Double,
    defaultValue: Double,
    range: ClosedRange<Double>
  ) -> Double {
    guard value.isFinite else { return defaultValue }
    return min(range.upperBound, max(range.lowerBound, value))
  }
}

nonisolated struct AlertPolicy: Sendable {
  private var configuration: AlertPolicyConfiguration
  private var activeKinds = Set<AlertKind>()
  private var lastEmission = [AlertKind: Date]()

  init(configuration: AlertPolicyConfiguration = .init()) {
    self.configuration = configuration
  }

  mutating func updateConfiguration(_ configuration: AlertPolicyConfiguration) {
    self.configuration = configuration
  }

  mutating func evaluate(snapshot: SystemSnapshot, now: Date = Date()) -> [AlertEvent] {
    var events: [AlertEvent] = []
    evaluatePower(snapshot: snapshot, now: now, events: &events)
    evaluateMemory(snapshot: snapshot, now: now, events: &events)
    evaluateBattery(snapshot: snapshot, now: now, events: &events)
    return events
  }

  mutating func reset() {
    activeKinds.removeAll(keepingCapacity: true)
    lastEmission.removeAll(keepingCapacity: true)
  }

  mutating func markDeliveryFailed(_ kind: AlertKind) {
    activeKinds.remove(kind)
    lastEmission.removeValue(forKey: kind)
  }

  private mutating func evaluatePower(
    snapshot: SystemSnapshot,
    now: Date,
    events: inout [AlertEvent]
  ) {
    let assessment = snapshot.power.value
    let confidence = assessment?.confidence
    let validConfidence = confidence?.isFinite == true ? confidence : nil
    let active =
      assessment?.status == .insufficient
      && (validConfidence ?? 0) >= configuration.powerConfidenceThreshold

    transition(
      kind: .insufficientPower,
      isActive: active,
      now: now,
      event: AlertEvent(
        kind: .insufficientPower,
        title: L10n.string("Power adapter may be insufficient"),
        message: assessment?.explanation
          ?? L10n.string("Battery discharge continues while connected to power")),
      events: &events)
  }

  private mutating func evaluateMemory(
    snapshot: SystemSnapshot,
    now: Date,
    events: inout [AlertEvent]
  ) {
    let memory = snapshot.memory.value
    let usedPercent = validPercentage(memory?.usedPercent)
    let thresholdExceeded = (usedPercent ?? -1) >= configuration.memoryThresholdPercent
    let pressureActive =
      memory.map {
        $0.pressureLevel == .warning || $0.pressureLevel == .critical
      } ?? false

    transition(
      kind: .highMemory,
      isActive: thresholdExceeded || pressureActive,
      now: now,
      event: AlertEvent(
        kind: .highMemory,
        title: memoryAlertTitle(memory?.pressureLevel),
        message: memoryAlertMessage(memory, validUsedPercent: usedPercent)),
      events: &events)
  }

  private func memoryAlertTitle(_ level: MemoryPressureLevel?) -> String {
    switch level {
    case .critical: return L10n.string("Critical memory pressure")
    case .warning: return L10n.string("Memory pressure warning")
    default: return L10n.string("High memory usage")
    }
  }

  private func memoryAlertMessage(
    _ memory: MemoryStats?,
    validUsedPercent: Double?
  ) -> String {
    switch memory?.pressureLevel {
    case .critical:
      return L10n.string(
        "macOS reports critical memory pressure. Close memory-intensive applications.")
    case .warning:
      return L10n.string(
        "macOS reports elevated memory pressure. Performance may degrade.")
    default:
      if let percent = roundedPercentage(validUsedPercent) {
        return L10n.format("Memory usage reached %d%%", percent)
      }
      return L10n.string("Memory usage is above the configured threshold")
    }
  }

  private mutating func evaluateBattery(
    snapshot: SystemSnapshot,
    now: Date,
    events: inout [AlertEvent]
  ) {
    let battery = snapshot.battery.value
    let percentage = validPercentage(battery?.percentage)
    let active =
      battery?.state == .discharging
      && (percentage ?? 101) <= configuration.lowBatteryThresholdPercent

    transition(
      kind: .lowBattery,
      isActive: active,
      now: now,
      event: AlertEvent(
        kind: .lowBattery,
        title: L10n.string("Low battery"),
        message: roundedPercentage(percentage).map {
          L10n.format("Battery level is %d%%", $0)
        } ?? L10n.string("Battery level is low")),
      events: &events)
  }

  private func validPercentage(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (0...100).contains(value) else { return nil }
    return value
  }

  private func roundedPercentage(_ value: Double?) -> Int? {
    guard let value = validPercentage(value) else { return nil }
    return Int(value.rounded())
  }

  private mutating func transition(
    kind: AlertKind,
    isActive: Bool,
    now: Date,
    event: AlertEvent,
    events: inout [AlertEvent]
  ) {
    guard isActive else {
      activeKinds.remove(kind)
      return
    }

    guard !activeKinds.contains(kind) else { return }
    activeKinds.insert(kind)

    if let last = lastEmission[kind] {
      let elapsed = now.timeIntervalSince(last)
      if elapsed.isFinite, elapsed >= 0, elapsed < configuration.cooldown {
        return
      }
    }

    lastEmission[kind] = now
    events.append(event)
  }
}
