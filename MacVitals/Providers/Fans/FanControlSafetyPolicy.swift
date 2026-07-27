import Foundation

nonisolated enum FanThermalSeverity: String, Codable, Sendable, Equatable {
  case nominal
  case fair
  case serious
  case critical

  init(_ state: ProcessInfo.ThermalState) {
    switch state {
    case .nominal: self = .nominal
    case .fair: self = .fair
    case .serious: self = .serious
    case .critical: self = .critical
    @unknown default: self = .critical
    }
  }
}

nonisolated struct FanControlPlan: Codable, Sendable, Equatable {
  let fanIndex: Int
  let targetRPM: Double
  let leaseSeconds: TimeInterval
  let thermalSeverity: FanThermalSeverity
}

nonisolated struct FanControlRecoveryState: Sendable, Equatable {
  private(set) var deadlines: [Int: Date] = [:]

  var indexes: [Int] { deadlines.keys.sorted() }
  var isEmpty: Bool { deadlines.isEmpty }

  mutating func beginRecovery(index: Int, now: Date) {
    deadlines[index] = now
  }

  mutating func activate(index: Int, deadline: Date) {
    deadlines[index] = deadline
  }

  mutating func markRestored(index: Int) {
    deadlines.removeValue(forKey: index)
  }

  mutating func markAllRestored() {
    deadlines.removeAll()
  }

  func hasTrackedFan(excluding index: Int) -> Bool {
    deadlines.keys.contains { $0 != index }
  }

  func expired(at now: Date) -> [Int] {
    deadlines.compactMap { $0.value <= now ? $0.key : nil }.sorted()
  }
}

nonisolated enum FanControlSafetyError: LocalizedError, Sendable, Equatable {
  case invalidFan
  case invalidRange
  case invalidRequest
  case requestBelowSafetyFloor(Double)

  var errorDescription: String? {
    switch self {
    case .invalidFan: return "Fan index is outside the supported range"
    case .invalidRange: return "Fan minimum and maximum RPM are invalid"
    case .invalidRequest: return "Requested fan speed or lease is invalid"
    case .requestBelowSafetyFloor(let floor):
      return "Requested speed is below the safe cooling floor of \(Int(floor.rounded())) RPM"
    }
  }
}

nonisolated enum FanControlSafetyPolicy {
  static let minimumLeaseSeconds: TimeInterval = 30
  static let maximumLeaseSeconds: TimeInterval = 15 * 60
  static let minimumMaximumFraction = 0.55
  static let fairThermalMinimumFraction = 0.80

  static func safeBoostRange(for fan: FanReading) -> ClosedRange<Double>? {
    guard fan.index >= 0, fan.index < FanValueNormalizer.maximumFanCount,
      let minimum = FanValueNormalizer.rpm(fan.minimumRPM),
      let maximum = FanValueNormalizer.rpm(fan.maximumRPM),
      minimum > 0,
      maximum > minimum
    else { return nil }
    let current = FanValueNormalizer.rpm(fan.currentRPM) ?? minimum
    guard current <= maximum else { return nil }
    let floor = max(minimum, current, maximum * minimumMaximumFraction)
    return floor...maximum
  }

  static func plan(
    fan: FanReading,
    requestedRPM: Double,
    leaseSeconds: TimeInterval,
    thermalSeverity: FanThermalSeverity
  ) throws -> FanControlPlan {
    guard fan.index >= 0, fan.index < FanValueNormalizer.maximumFanCount else {
      throw FanControlSafetyError.invalidFan
    }
    guard let safeRange = safeBoostRange(for: fan) else {
      throw FanControlSafetyError.invalidRange
    }
    guard let requested = FanValueNormalizer.rpm(requestedRPM), requested > 0,
      leaseSeconds.isFinite, leaseSeconds > 0
    else {
      throw FanControlSafetyError.invalidRequest
    }
    guard requested >= safeRange.lowerBound else {
      throw FanControlSafetyError.requestBelowSafetyFloor(safeRange.lowerBound)
    }

    let thermallyAdjusted: Double
    switch thermalSeverity {
    case .nominal:
      thermallyAdjusted = requested
    case .fair:
      thermallyAdjusted = max(requested, safeRange.upperBound * fairThermalMinimumFraction)
    case .serious, .critical:
      thermallyAdjusted = safeRange.upperBound
    }

    return FanControlPlan(
      fanIndex: fan.index,
      targetRPM: min(safeRange.upperBound, thermallyAdjusted),
      leaseSeconds: min(maximumLeaseSeconds, max(minimumLeaseSeconds, leaseSeconds)),
      thermalSeverity: thermalSeverity)
  }
}
