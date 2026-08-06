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

  static func shouldPublishCompletedSample(
    completedSession: UInt64,
    currentSession: UInt64,
    completedRequest: UInt64,
    currentRequest: UInt64?
  ) -> Bool {
    completedSession == currentSession && currentRequest == completedRequest
  }
}
