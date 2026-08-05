import Foundation

nonisolated enum ProcessSamplingResultDisposition: Sendable, Equatable {
  case commit
  case clearOnly
  case ignore
}

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

  static func resultDisposition(
    requestID: UUID,
    activeRequestID: UUID?,
    hasSubscribers: Bool
  ) -> ProcessSamplingResultDisposition {
    guard activeRequestID == requestID else { return .ignore }
    return hasSubscribers ? .commit : .clearOnly
  }
}
