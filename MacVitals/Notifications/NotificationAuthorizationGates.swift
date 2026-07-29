import Foundation

nonisolated struct NotificationAuthorizationRequestGate: Sendable {
  private(set) var isInFlight = false

  mutating func begin() -> Bool {
    guard !isInFlight else { return false }
    isInFlight = true
    return true
  }

  mutating func finish() {
    isInFlight = false
  }
}

nonisolated struct NotificationAuthorizationRefreshGate: Sendable {
  private var generation: UInt64 = 0

  mutating func begin() -> UInt64 {
    generation &+= 1
    return generation
  }

  mutating func invalidate() {
    generation &+= 1
  }

  func isCurrent(_ token: UInt64) -> Bool {
    token == generation
  }
}

nonisolated struct NotificationDeliveryCallbackGate: Sendable {
  private var generation: UInt64 = 0

  var token: UInt64 { generation }

  mutating func invalidate() {
    generation &+= 1
  }

  func isCurrent(_ token: UInt64) -> Bool {
    token == generation
  }
}

nonisolated struct NotificationDeliveryRetryGate: Sendable {
  static let defaultRetryDelay: TimeInterval = 60
  static let maximumRetryDelay: TimeInterval = 60 * 60

  private struct Window: Sendable {
    let failedAt: Date
    let retryDelay: TimeInterval

    init(failedAt: Date, retryDelay: TimeInterval) {
      self.failedAt =
        failedAt.timeIntervalSinceReferenceDate.isFinite
        ? failedAt
        : Date(timeIntervalSinceReferenceDate: 0)
      self.retryDelay = Self.normalized(retryDelay)
    }

    func isReady(at now: Date) -> Bool {
      let elapsed = now.timeIntervalSince(failedAt)
      guard elapsed.isFinite else { return true }
      return elapsed < 0 || elapsed >= retryDelay
    }

    private static func normalized(_ value: TimeInterval) -> TimeInterval {
      guard value.isFinite else { return NotificationDeliveryRetryGate.defaultRetryDelay }
      return min(NotificationDeliveryRetryGate.maximumRetryDelay, max(1, value))
    }
  }

  private var windows: [AlertKind: Window] = [:]

  var pendingCount: Int { windows.count }

  mutating func markFailed(
    _ kind: AlertKind,
    at date: Date = Date(),
    retryDelay: TimeInterval = defaultRetryDelay
  ) {
    windows[kind] = Window(failedAt: date, retryDelay: retryDelay)
  }

  mutating func canAttempt(_ kind: AlertKind, at date: Date = Date()) -> Bool {
    guard let window = windows[kind] else { return true }
    guard window.isReady(at: date) else { return false }
    windows.removeValue(forKey: kind)
    return true
  }

  mutating func reset() {
    windows.removeAll(keepingCapacity: true)
  }
}
