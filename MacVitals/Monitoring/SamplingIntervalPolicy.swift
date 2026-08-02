import Foundation

nonisolated enum SamplingPowerSource: String, Codable, Sendable {
  case battery
  case externalPower

  static func resolve(
    externalPowerConnected: Bool?,
    adapterConnected: Bool?,
    batteryPresent: Bool?,
    fallback: Self = .externalPower
  ) -> Self {
    if externalPowerConnected == true || adapterConnected == true || batteryPresent == false {
      return .externalPower
    }
    if externalPowerConnected == false {
      return .battery
    }
    return fallback
  }
}

nonisolated struct SamplingIntervalPreferences: Equatable, Sendable {
  let onBattery: TimeInterval
  let onExternalPower: TimeInterval

  init(onBattery: TimeInterval, onExternalPower: TimeInterval) {
    self.onBattery = SamplingIntervalPolicy.normalized(onBattery)
    self.onExternalPower = SamplingIntervalPolicy.normalized(onExternalPower)
  }

  static func resolve(
    legacyValue: TimeInterval?,
    batteryValue: TimeInterval?,
    externalPowerValue: TimeInterval?
  ) -> Self {
    let legacy = SamplingIntervalPolicy.normalized(
      legacyValue ?? SamplingIntervalPolicy.defaultValue)
    return Self(
      onBattery: batteryValue ?? legacy,
      onExternalPower: externalPowerValue ?? legacy)
  }

  func interval(for source: SamplingPowerSource) -> TimeInterval {
    switch source {
    case .battery: return onBattery
    case .externalPower: return onExternalPower
    }
  }
}

nonisolated enum SamplingIntervalPolicy {
  static let supportedValues: [TimeInterval] = [1, 2, 5, 10, 15, 30]
  static let defaultValue: TimeInterval = 5
  static let temperatureMinimumInterval: TimeInterval = 5
  static let historyDuration: TimeInterval = 60 * 60

  static func normalized(_ value: TimeInterval) -> TimeInterval {
    guard value.isFinite, value > 0 else { return defaultValue }
    return supportedValues.min { lhs, rhs in
      let lhsDistance = abs(lhs - value)
      let rhsDistance = abs(rhs - value)
      if lhsDistance == rhsDistance { return lhs < rhs }
      return lhsDistance < rhsDistance
    } ?? defaultValue
  }

  static func historyCapacity(for interval: TimeInterval) -> Int {
    let normalizedInterval = normalized(interval)
    let samples = Int(ceil(historyDuration / normalizedInterval))
    return max(120, min(3_600, samples))
  }

  static func sleepNanoseconds(
    intervalSeconds: TimeInterval,
    elapsedMilliseconds: Double
  ) -> UInt64 {
    let normalizedInterval = normalized(intervalSeconds)
    let delay = SamplingTimingMath.remainingDelaySeconds(
      intervalSeconds: normalizedInterval,
      elapsedMilliseconds: elapsedMilliseconds)
    guard delay.isFinite, delay > 0 else { return 0 }
    let nanoseconds = delay * 1_000_000_000
    guard nanoseconds.isFinite, nanoseconds > 0 else { return 0 }
    return UInt64(min(nanoseconds, Double(UInt64.max)))
  }
}
