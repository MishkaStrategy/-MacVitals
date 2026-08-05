import Foundation

nonisolated enum FanTerminationPolicy {
  static let restoreTimeoutNanoseconds: UInt64 = 2_000_000_000

  static func shouldDelayTermination(for state: FanControlClientState) -> Bool {
    state.canControl
  }
}

@MainActor
final class ApplicationTerminationGate {
  private(set) var isPending = false

  func begin() -> Bool {
    guard !isPending else { return false }
    isPending = true
    return true
  }

  func complete(_ action: () -> Void) {
    guard isPending else { return }
    isPending = false
    action()
  }

  func cancel() {
    isPending = false
  }
}
