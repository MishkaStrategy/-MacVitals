import Foundation

nonisolated enum HistoricalConsumptionTerminationPolicy {
  static let flushTimeoutNanoseconds: UInt64 = 2_000_000_000
}

@MainActor
final class HistoricalConsumptionTerminationCoordinator {
  enum Outcome: Sendable, Equatable {
    case flushed
    case timedOut
  }

  private(set) var isPending = false
  private var flushTask: Task<Void, Never>?
  private var timeoutTask: Task<Void, Never>?

  @discardableResult
  func begin(
    timeoutNanoseconds: UInt64 = HistoricalConsumptionTerminationPolicy.flushTimeoutNanoseconds,
    flush: @escaping @MainActor () async -> Void,
    completion: @escaping @MainActor (Outcome) -> Void
  ) -> Bool {
    guard !isPending else { return false }
    isPending = true

    flushTask = Task { [weak self] in
      await flush()
      guard !Task.isCancelled else { return }
      self?.finish(outcome: .flushed, completion: completion)
    }

    timeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: timeoutNanoseconds)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self?.finish(outcome: .timedOut, completion: completion)
    }
    return true
  }

  func cancel() {
    isPending = false
    flushTask?.cancel()
    flushTask = nil
    timeoutTask?.cancel()
    timeoutTask = nil
  }

  private func finish(
    outcome: Outcome,
    completion: @escaping @MainActor (Outcome) -> Void
  ) {
    guard isPending else { return }
    isPending = false
    flushTask?.cancel()
    flushTask = nil
    timeoutTask?.cancel()
    timeoutTask = nil
    completion(outcome)
  }

  deinit {
    flushTask?.cancel()
    timeoutTask?.cancel()
  }
}
