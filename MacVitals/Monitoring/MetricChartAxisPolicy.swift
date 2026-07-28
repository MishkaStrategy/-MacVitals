import Foundation

nonisolated enum MetricChartAxisPolicy {
  static let shortRangeDuration: TimeInterval = 5 * 60
  static let shortRangeMinorSecondStride = 5

  static func minorSecondStride(for duration: TimeInterval) -> Int? {
    guard duration.isFinite, duration > 0, duration <= shortRangeDuration else { return nil }
    return shortRangeMinorSecondStride
  }
}
