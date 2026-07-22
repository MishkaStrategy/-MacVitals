import Foundation

nonisolated enum SamplingIntervalPolicy {
  static let supportedValues: [TimeInterval] = [0.5, 1, 2, 5, 10]
  static let defaultValue: TimeInterval = 2

  static func normalized(_ value: TimeInterval) -> TimeInterval {
    guard value.isFinite, value > 0 else { return defaultValue }
    return supportedValues.min { lhs, rhs in
      let lhsDistance = abs(lhs - value)
      let rhsDistance = abs(rhs - value)
      if lhsDistance == rhsDistance { return lhs < rhs }
      return lhsDistance < rhsDistance
    } ?? defaultValue
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