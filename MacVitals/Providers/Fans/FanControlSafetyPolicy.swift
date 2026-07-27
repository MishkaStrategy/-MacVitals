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

  static func plan(
    fan: FanReading,
    requestedRPM: Double,
    leaseSeconds: TimeInterval,
    thermalSeverity: FanThermalSeverity
  ) throws -> FanControlPlan {
    guard fan.index >= 0, fan.index < FanValueNormalizer.maximumFanCount else {
      throw FanControlSafetyError.invalidFan
    }
    guard let minimum = FanValueNormalizer.rpm(fan.minimumRPM),
      let maximum = FanValueNormalizer.rpm(fan.maximumRPM),
      minimum > 0,
      maximum > minimum
    else {
      throw FanControlSafetyError.invalidRange
    }
    guard let requested = FanValueNormalizer.rpm(requestedRPM), requested > 0,
      leaseSeconds.isFinite, leaseSeconds > 0
    else {
      throw FanControlSafetyError.invalidRequest
    }

    let current = FanValueNormalizer.rpm(fan.currentRPM) ?? minimum
    let safetyFloor = min(maximum, max(minimum, current, maximum * minimumMaximumFraction))
    guard requested >= safetyFloor else {
      throw FanControlSafetyError.requestBelowSafetyFloor(safetyFloor)
    }

    let thermallyAdjusted: Double
    switch thermalSeverity {
    case .nominal:
      thermallyAdjusted = requested
    case .fair:
      thermallyAdjusted = max(requested, maximum * fairThermalMinimumFraction)
    case .serious, .critical:
      thermallyAdjusted = maximum
    }

    return FanControlPlan(
      fanIndex: fan.index,
      targetRPM: min(maximum, thermallyAdjusted),
      leaseSeconds: min(maximumLeaseSeconds, max(minimumLeaseSeconds, leaseSeconds)),
      thermalSeverity: thermalSeverity)
  }
}
