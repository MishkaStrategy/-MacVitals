import Foundation

final class SamplingActivityLease: @unchecked Sendable {
  typealias Token = any NSObjectProtocol

  private let lock = NSLock()
  private let beginActivity: () -> Token
  private let endActivity: (Token) -> Void
  private var token: Token?

  init(
    beginActivity: @escaping () -> Token = {
      ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep,
        reason: "Continuous system monitoring")
    },
    endActivity: @escaping (Token) -> Void = { token in
      ProcessInfo.processInfo.endActivity(token)
    }
  ) {
    self.beginActivity = beginActivity
    self.endActivity = endActivity
  }

  func start() {
    lock.lock()
    defer { lock.unlock() }
    guard token == nil else { return }
    token = beginActivity()
  }

  func stop() {
    let activity: Token?
    lock.lock()
    activity = token
    token = nil
    lock.unlock()

    if let activity {
      endActivity(activity)
    }
  }

  deinit {
    stop()
  }
}
