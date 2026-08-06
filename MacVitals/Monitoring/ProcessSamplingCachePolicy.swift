import Foundation

nonisolated enum ProcessSamplingCachePolicy {
  static func freshnessWindow(minimumInterval: TimeInterval) -> TimeInterval {
    let normalizedInterval = minimumInterval.isFinite ? max(0, minimumInterval) : 0
    return max(0.25, normalizedInterval * 0.8)
  }

  static func isFresh(
    timestamp: Date,
    now: Date,
    minimumInterval: TimeInterval
  ) -> Bool {
    guard timestamp != .distantPast else { return false }
    let age = now.timeIntervalSince(timestamp)
    return age.isFinite
      && age >= 0
      && age < freshnessWindow(minimumInterval: minimumInterval)
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
