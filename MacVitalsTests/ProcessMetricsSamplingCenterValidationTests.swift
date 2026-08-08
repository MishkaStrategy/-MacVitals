import Foundation
import XCTest

@testable import MacVitals

final class ProcessMetricsSamplingCenterValidationTests: XCTestCase {
  func testConcurrentSubscribersReceiveTheSameInFlightSnapshot() async {
    let center = ProcessMetricsSamplingCenter()
    let firstSubscriber = UUID()
    let secondSubscriber = UUID()

    await center.subscribe(firstSubscriber)
    await center.subscribe(secondSubscriber)

    async let first = center.sample(runningApplications: [], minimumInterval: 2)
    async let second = center.sample(runningApplications: [], minimumInterval: 2)
    let (firstSnapshot, secondSnapshot) = await (first, second)

    XCTAssertEqual(firstSnapshot, secondSnapshot)
    XCTAssertGreaterThan(firstSnapshot.sampledProcessCount, 0)

    let cached = await center.sample(runningApplications: [], minimumInterval: 2)
    XCTAssertEqual(cached, firstSnapshot)

    await center.unsubscribe(firstSubscriber)
    await center.unsubscribe(secondSubscriber)
  }

  func testRemainingSubscriberKeepsSharedCacheUntilLastSubscriberStops() async {
    let center = ProcessMetricsSamplingCenter()
    let firstSubscriber = UUID()
    let secondSubscriber = UUID()
    let replacementSubscriber = UUID()

    await center.subscribe(firstSubscriber)
    await center.subscribe(secondSubscriber)
    let initial = await center.sample(runningApplications: [], minimumInterval: 30)

    await center.unsubscribe(firstSubscriber)
    let whileSecondSubscriberRemains = await center.sample(
      runningApplications: [], minimumInterval: 30)
    XCTAssertEqual(whileSecondSubscriberRemains, initial)

    await center.unsubscribe(secondSubscriber)
    await center.subscribe(replacementSubscriber)
    let afterLastSubscriberRestart = await center.sample(
      runningApplications: [], minimumInterval: 30)

    XCTAssertNotEqual(afterLastSubscriberRestart.timestamp, initial.timestamp)
    XCTAssertGreaterThan(afterLastSubscriberRestart.sampledProcessCount, 0)

    await center.unsubscribe(replacementSubscriber)
  }

  func testExpiredIntervalStillCoalescesTwoConsumersIntoOneSnapshot() async throws {
    let center = ProcessMetricsSamplingCenter()
    let firstSubscriber = UUID()
    let secondSubscriber = UUID()

    await center.subscribe(firstSubscriber)
    await center.subscribe(secondSubscriber)
    let first = await center.sample(runningApplications: [], minimumInterval: 1)

    try await Task.sleep(for: .seconds(1))

    async let refreshedFirst = center.sample(runningApplications: [], minimumInterval: 1)
    async let refreshedSecond = center.sample(runningApplications: [], minimumInterval: 1)
    let (left, right) = await (refreshedFirst, refreshedSecond)

    XCTAssertEqual(left, right)
    XCTAssertGreaterThan(left.timestamp, first.timestamp)
    XCTAssertGreaterThan(left.sampledProcessCount, 0)

    await center.unsubscribe(firstSubscriber)
    await center.unsubscribe(secondSubscriber)
  }

  @MainActor
  func testLivePrimaryConsumerAndAutonomousHistoryShareSamplingHost() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard
      let readyPath = environment["MACVITALS_SHARED_SAMPLING_READY_FILE"],
      !readyPath.isEmpty,
      let completePath = environment["MACVITALS_SHARED_SAMPLING_COMPLETE_FILE"],
      !completePath.isEmpty
    else {
      throw XCTSkip("Live shared-sampling evidence requires explicit validation marker paths")
    }

    let history = HistoricalConsumptionCenter.shared
    let monitor = ProcessConsumersMonitor()
    let initialRevision = history.revision

    history.start(interval: 1, initialDelay: 0)
    monitor.start(interval: 1)
    defer { monitor.stop() }

    try await waitUntil(timeout: 20) {
      history.isCollecting
        && monitor.isRunning
        && monitor.snapshot.sampledProcessCount > 0
        && !monitor.snapshot.applications.isEmpty
    }

    let firstLiveTimestamp = monitor.snapshot.timestamp
    try writeMarker(path: readyPath, value: "primary-and-history-active\n")

    try await Task.sleep(for: .seconds(70))

    XCTAssertTrue(history.isCollecting)
    XCTAssertTrue(monitor.isRunning)
    XCTAssertGreaterThan(monitor.snapshot.timestamp, firstLiveTimestamp)
    XCTAssertGreaterThan(monitor.snapshot.sampledProcessCount, 0)
    XCTAssertFalse(monitor.snapshot.applications.isEmpty)
    XCTAssertGreaterThan(history.revision, initialRevision)
    XCTAssertNotNil(history.historyStartedAt)

    let memoryLeaders = await history.leaders(metric: .memory, range: .oneHour)
    XCTAssertFalse(memoryLeaders.isEmpty)
    let liveIDs = Set(monitor.snapshot.applications.map(\.id))
    let historicalIDs = Set(memoryLeaders.map(\.id))
    XCTAssertFalse(
      liveIDs.isDisjoint(with: historicalIDs),
      "Live process snapshot and autonomous history have no shared application identity")

    try writeMarker(
      path: completePath,
      value: "history-advanced-and-overlapped-live-snapshot\n")
  }

  @MainActor
  private func waitUntil(
    timeout: TimeInterval,
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(200))
    }
    XCTFail("Timed out waiting for live primary/history multi-consumer state")
    throw ValidationError.timedOut
  }

  private func writeMarker(path: String, value: String) throws {
    try Data(value.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  private enum ValidationError: Error {
    case timedOut
  }
}
