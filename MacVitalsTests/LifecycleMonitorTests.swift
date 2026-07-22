import Foundation
import XCTest
@testable import MacVitals

@MainActor
final class LifecycleMonitorTests: XCTestCase {
  func testStartIsIdempotentAndStopAllowsRestart() {
    let monitor = LifecycleMonitor(center: NotificationCenter())
    let coordinator = MetricsCoordinator()

    XCTAssertFalse(monitor.isStarted)
    XCTAssertEqual(monitor.observerCount, 0)

    monitor.start(coordinator: coordinator)
    XCTAssertTrue(monitor.isStarted)
    XCTAssertEqual(monitor.observerCount, 2)

    monitor.start(coordinator: coordinator)
    XCTAssertEqual(monitor.observerCount, 2)

    monitor.stop()
    XCTAssertFalse(monitor.isStarted)
    XCTAssertEqual(monitor.observerCount, 0)

    monitor.start(coordinator: coordinator)
    XCTAssertTrue(monitor.isStarted)
    XCTAssertEqual(monitor.observerCount, 2)

    monitor.stop()
  }
}