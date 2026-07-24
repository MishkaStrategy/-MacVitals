import Foundation
import XCTest

@testable import MacVitals

@MainActor
final class LifecycleMonitorTests: XCTestCase {
  func testStartIsIdempotentAndStopAllowsRestart() {
    let monitor = LifecycleMonitor(center: NotificationCenter())
    let coordinator = LifecycleCoordinatorSpy()

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

  func testSleepAndWakeAreDeliveredSynchronouslyInPostingOrder() {
    let center = NotificationCenter()
    let monitor = LifecycleMonitor(center: center)
    let coordinator = LifecycleCoordinatorSpy()
    monitor.start(coordinator: coordinator)

    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)

    XCTAssertEqual(coordinator.events, [.sleep, .wake])
    monitor.stop()
  }

  func testStopPreventsLaterLifecycleDelivery() {
    let center = NotificationCenter()
    let monitor = LifecycleMonitor(center: center)
    let coordinator = LifecycleCoordinatorSpy()
    monitor.start(coordinator: coordinator)
    monitor.stop()

    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)

    XCTAssertTrue(coordinator.events.isEmpty)
  }
}

@MainActor
private final class LifecycleCoordinatorSpy: LifecycleCoordinating {
  enum Event: Equatable {
    case sleep
    case wake
  }

  private(set) var events: [Event] = []

  func handleSleep() {
    events.append(.sleep)
  }

  func handleWake() {
    events.append(.wake)
  }
}
