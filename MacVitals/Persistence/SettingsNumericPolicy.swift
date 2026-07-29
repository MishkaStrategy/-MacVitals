import Foundation

nonisolated enum SettingsNumericPolicy {
  static let defaultMemoryAlertThreshold = 90.0
  static let defaultLowBatteryAlertThreshold = 15.0

  static func memoryAlertThreshold(_ value: Double) -> Double {
    bounded(
      value,
      defaultValue: defaultMemoryAlertThreshold,
      range: 50...100)
  }

  static func lowBatteryAlertThreshold(_ value: Double) -> Double {
    bounded(
      value,
      defaultValue: defaultLowBatteryAlertThreshold,
      range: 5...50)
  }

  private static func bounded(
    _ value: Double,
    defaultValue: Double,
    range: ClosedRange<Double>
  ) -> Double {
    guard value.isFinite, value > 0 else { return defaultValue }
    return min(range.upperBound, max(range.lowerBound, value))
  }
}