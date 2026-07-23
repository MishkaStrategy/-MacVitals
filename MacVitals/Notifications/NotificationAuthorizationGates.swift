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
