import XCTest
@testable import MacVitals

final class ProcessMetricsSamplingCenterTests: XCTestCase {
  func testSubscribersReuseFreshSnapshot() async {
    let center = ProcessMetricsSamplingCenter()
    let firstSubscriber = UUID()
    let secondSubscriber = UUID()

    await center.subscribe(firstSubscriber)
    await center.subscribe(secondSubscriber)

    let first = await center.sample(
      runningApplications: [],
      minimumInterval: 30)
    let second = await center.sample(
      runningApplications: [],
      minimumInterval: 30)

    XCTAssertEqual(first, second)
    XCTAssertEqual(first.timestamp, second.timestamp)

    await center.unsubscribe(firstSubscriber)
    await center.unsubscribe(secondSubscriber)
  }

  func testLastSubscriberEndsSessionAndResetsCache() async {
    let center = ProcessMetricsSamplingCenter()
    let firstSubscriber = UUID()

    await center.subscribe(firstSubscriber)
    let first = await center.sample(
      runningApplications: [],
      minimumInterval: 30)
    await center.unsubscribe(firstSubscriber)

    let secondSubscriber = UUID()
    await center.subscribe(secondSubscriber)
    let second = await center.sample(
      runningApplications: [],
      minimumInterval: 30)
    await center.unsubscribe(secondSubscriber)

    XCTAssertGreaterThanOrEqual(second.timestamp, first.timestamp)
    XCTAssertNotEqual(second.timestamp, .distantPast)
  }
}
