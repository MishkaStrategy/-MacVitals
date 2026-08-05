import Foundation

nonisolated enum ProcessSamplingCachePolicy {
  static func freshnessWindow(minimumInterval: TimeInterval) -> TimeInterval {
    max(0.25, minimumInterval * 0.8)
  }

  static func isFresh(
    timestamp: Date,
    now: Date,
    minimumInterval: TimeInterval
  ) -> Bool {
    guard timestamp != .distantPast else { return false }
    return now.timeIntervalSince(timestamp) < freshnessWindow(minimumInterval: minimumInterval)
  }
}
