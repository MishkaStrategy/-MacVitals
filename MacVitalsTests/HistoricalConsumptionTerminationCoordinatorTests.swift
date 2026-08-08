import XCTest

@testable import MacVitals

@MainActor
final class HistoricalConsumptionTerminationCoordinatorTests: XCTestCase {
  func testFlushCompletionWinsAndCompletesExactlyOnce() async throws {
    let coordinator = HistoricalConsumptionTerminationCoordinator()
    var outcomes: [HistoricalConsumptionTerminationCoordinator.Outcome] = []

    XCTAssertTrue(
      coordinator.begin(
        timeoutNanoseconds: 500_000_000,
        flush: {},
        completion: { outcomes.append($0) }))
    XCTAssertFalse(
      coordinator.begin(
        timeoutNanoseconds: 10_000_000,
        flush: {},
        completion: { outcomes.append($0) }))

    try await waitUntil { outcomes == [.flushed] }
    XCTAssertFalse(coordinator.isPending)
    XCTAssertFalse(
      coordinator.begin(
        timeoutNanoseconds: 10_000_000,
        flush: {},
        completion: { outcomes.append($0) }),
      "A completed termination sequence must remain one-shot")

    try await Task.sleep(nanoseconds: 600_000_000)
    XCTAssertEqual(outcomes, [.flushed])
  }

  func testTimeoutWinsCancelsSlowFlushAndCompletesExactlyOnce() async throws {
    let coordinator = HistoricalConsumptionTerminationCoordinator()
    var outcomes: [HistoricalConsumptionTerminationCoordinator.Outcome] = []
    var flushObservedCancellation = false

    XCTAssertTrue(
      coordinator.begin(
        timeoutNanoseconds: 20_000_000,
        flush: {
          do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
          } catch {
            flushObservedCancellation = true
          }
        },
        completion: { outcomes.append($0) }))

    try await waitUntil { outcomes == [.timedOut] }
    try await waitUntil { flushObservedCancellation }
    XCTAssertFalse(coordinator.isPending)
    XCTAssertFalse(
      coordinator.begin(
        timeoutNanoseconds: 10_000_000,
        flush: {},
        completion: { outcomes.append($0) }),
      "A timed-out termination sequence must remain one-shot")

    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertEqual(outcomes, [.timedOut])
  }

  func testLateFlushReturnAfterTimeoutCannotReplyTwice() async throws {
    let coordinator = HistoricalConsumptionTerminationCoordinator()
    var outcomes: [HistoricalConsumptionTerminationCoordinator.Outcome] = []
    var flushReturned = false

    XCTAssertTrue(
      coordinator.begin(
        timeoutNanoseconds: 20_000_000,
        flush: {
          do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
          } catch {
            // Simulate a non-cancellation-aware persistence call returning after timeout.
          }
          flushReturned = true
        },
        completion: { outcomes.append($0) }))

    try await waitUntil { outcomes == [.timedOut] }
    try await waitUntil { flushReturned }
    XCTAssertEqual(outcomes, [.timedOut])
    XCTAssertFalse(coordinator.isPending)
  }

  func testCancelPreventsFlushOrTimeoutCompletion() async throws {
    let coordinator = HistoricalConsumptionTerminationCoordinator()
    var outcomes: [HistoricalConsumptionTerminationCoordinator.Outcome] = []

    XCTAssertTrue(
      coordinator.begin(
        timeoutNanoseconds: 20_000_000,
        flush: {
          try? await Task.sleep(nanoseconds: 1_000_000_000)
        },
        completion: { outcomes.append($0) }))

    coordinator.cancel()
    XCTAssertFalse(coordinator.isPending)
    try await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(outcomes.isEmpty)
  }

  private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let started = ContinuousClock.now
    while !condition() {
      if ContinuousClock.now - started > .nanoseconds(Int64(timeoutNanoseconds)) {
        XCTFail("Timed out waiting for termination coordinator state")
        throw TestError.timedOut
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  private enum TestError: Error {
    case timedOut
  }
}
