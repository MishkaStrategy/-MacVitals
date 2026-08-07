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
}
