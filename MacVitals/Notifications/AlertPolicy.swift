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
  var memoryThresholdPercent: Double
  var lowBatteryThresholdPercent: Double
  var powerConfidenceThreshold: Double
  var cooldown: TimeInterval

  init(
    memoryThresholdPercent: Double = 90,
    lowBatteryThresholdPercent: Double = 15,
    powerConfidenceThreshold: Double = 0.8,
    cooldown: TimeInterval = 15 * 60
  ) {
    self.memoryThresholdPercent = min(100, max(1, memoryThresholdPercent))
    self.lowBatteryThresholdPercent = min(100, max(1, lowBatteryThresholdPercent))
    self.powerConfidenceThreshold = min(1, max(0, powerConfidenceThreshold))
    self.cooldown = max(0, cooldown)
  }
}

nonisolated struct AlertPolicy: Sendable {
  private let configuration: AlertPolicyConfiguration
  private var activeKinds = Set<AlertKind>()
  private var lastEmission = [AlertKind: Date]()

  init(configuration: AlertPolicyConfiguration = .init()) {
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

  private mutating func evaluatePower(
    snapshot: SystemSnapshot,
    now: Date,
    events: inout [AlertEvent]
  ) {
    let assessment = snapshot.power.value
    let active = assessment?.status == .insufficient
      && (assessment?.confidence ?? 0) >= configuration.powerConfidenceThreshold

    transition(
      kind: .insufficientPower,
      isActive: active,
      now: now,
      event: AlertEvent(
        kind: .insufficientPower,
        title: "Power adapter may be insufficient",
        message: assessment?.explanation ?? "Battery discharge continues while connected to power"),
      events: &events)
  }

  private mutating func evaluateMemory(
    snapshot: SystemSnapshot,
    now: Date,
    events: inout [AlertEvent]
  ) {
    let usedPercent = snapshot.memory.value?.usedPercent
    let active = usedPercent.map { $0 >= configuration.memoryThresholdPercent } ?? false

    transition(
      kind: .highMemory,
      isActive: active,
      now: now,
      event: AlertEvent(
        kind: .highMemory,
        title: "High memory usage",
        message: usedPercent.map { "Memory usage reached \(Int($0.rounded()))%" }
          ?? "Memory usage is above the configured threshold"),
      events: &events)
  }

  private mutating func evaluateBattery(
    snapshot: SystemSnapshot,
    now: Date,
    events: inout [AlertEvent]
  ) {
    let battery = snapshot.battery.value
    let active = battery?.state == .discharging
      && (battery?.percentage ?? 101) <= configuration.lowBatteryThresholdPercent

    transition(
      kind: .lowBattery,
      isActive: active,
      now: now,
      event: AlertEvent(
        kind: .lowBattery,
        title: "Low battery",
        message: battery?.percentage.map { "Battery level is \(Int($0.rounded()))%" }
          ?? "Battery level is low"),
      events: &events)
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

    if let last = lastEmission[kind], now.timeIntervalSince(last) < configuration.cooldown {
      return
    }

    lastEmission[kind] = now
    events.append(event)
  }
}
