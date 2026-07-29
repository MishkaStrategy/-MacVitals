import UserNotifications
import XCTest

@testable import MacVitals

final class NotificationAuthorizationTests: XCTestCase {
  func testSystemAuthorizationStatusesMapCorrectly() {
    XCTAssertEqual(NotificationAuthorizationMapper.state(for: .notDetermined), .notDetermined)
    XCTAssertEqual(NotificationAuthorizationMapper.state(for: .denied), .denied)
    XCTAssertEqual(NotificationAuthorizationMapper.state(for: .authorized), .authorized)
    XCTAssertEqual(NotificationAuthorizationMapper.state(for: .provisional), .provisional)
  }

  func testOnlyAuthorizedStatesCanDeliver() {
    XCTAssertFalse(NotificationAuthorizationState.unknown.canDeliver)
    XCTAssertFalse(NotificationAuthorizationState.notDetermined.canDeliver)
    XCTAssertFalse(NotificationAuthorizationState.denied.canDeliver)
    XCTAssertTrue(NotificationAuthorizationState.authorized.canDeliver)
    XCTAssertTrue(NotificationAuthorizationState.provisional.canDeliver)
    XCTAssertFalse(NotificationAuthorizationState.failed("failure").canDeliver)
  }

  func testDeniedAndFailureStatesExposeActionableMessages() {
    XCTAssertNotNil(NotificationAuthorizationState.denied.message)
    XCTAssertEqual(NotificationAuthorizationState.failed("failure").message, "failure")
    XCTAssertNil(NotificationAuthorizationState.authorized.message)
  }

  func testAuthorizationRequestGateRejectsConcurrentRequestsUntilCompletion() {
    var gate = NotificationAuthorizationRequestGate()

    XCTAssertTrue(gate.begin())
    XCTAssertTrue(gate.isInFlight)
    XCTAssertFalse(gate.begin())
    XCTAssertTrue(gate.isInFlight)

    gate.finish()

    XCTAssertFalse(gate.isInFlight)
    XCTAssertTrue(gate.begin())
  }

  func testAuthorizationRefreshGateAcceptsOnlyLatestGeneration() {
    var gate = NotificationAuthorizationRefreshGate()
    let first = gate.begin()
    let second = gate.begin()

    XCTAssertFalse(gate.isCurrent(first))
    XCTAssertTrue(gate.isCurrent(second))
  }

  func testAuthorizationRefreshGateInvalidatesOutstandingGeneration() {
    var gate = NotificationAuthorizationRefreshGate()
    let token = gate.begin()

    gate.invalidate()

    XCTAssertFalse(gate.isCurrent(token))
  }

  func testDeliveryCallbackGateInvalidatesPreviousSession() {
    var gate = NotificationDeliveryCallbackGate()
    let firstSession = gate.token

    gate.invalidate()
    let secondSession = gate.token

    XCTAssertFalse(gate.isCurrent(firstSession))
    XCTAssertTrue(gate.isCurrent(secondSession))
  }

  func testDeliveryRetryGateBlocksUntilBoundaryAndThenClears() {
    var gate = NotificationDeliveryRetryGate()
    let failedAt = Date(timeIntervalSince1970: 1_000)

    gate.markFailed(.highMemory, at: failedAt, retryDelay: 30)

    XCTAssertEqual(gate.pendingCount, 1)
    XCTAssertFalse(gate.canAttempt(.highMemory, at: failedAt.addingTimeInterval(29.999)))
    XCTAssertTrue(gate.canAttempt(.highMemory, at: failedAt.addingTimeInterval(30)))
    XCTAssertEqual(gate.pendingCount, 0)
    XCTAssertTrue(gate.canAttempt(.highMemory, at: failedAt.addingTimeInterval(31)))
  }

  func testDeliveryRetryGateIsIndependentPerAlertKind() {
    var gate = NotificationDeliveryRetryGate()
    let failedAt = Date(timeIntervalSince1970: 2_000)

    gate.markFailed(.highMemory, at: failedAt, retryDelay: 60)
    gate.markFailed(.lowBattery, at: failedAt, retryDelay: 10)

    XCTAssertFalse(gate.canAttempt(.highMemory, at: failedAt.addingTimeInterval(10)))
    XCTAssertTrue(gate.canAttempt(.lowBattery, at: failedAt.addingTimeInterval(10)))
    XCTAssertEqual(gate.pendingCount, 1)
  }

  func testDeliveryRetryGateFailsOpenAfterClockRollback() {
    var gate = NotificationDeliveryRetryGate()
    let failedAt = Date(timeIntervalSince1970: 3_000)

    gate.markFailed(.insufficientPower, at: failedAt, retryDelay: 60)

    XCTAssertTrue(gate.canAttempt(.insufficientPower, at: failedAt.addingTimeInterval(-1)))
    XCTAssertEqual(gate.pendingCount, 0)
  }

  func testDeliveryRetryGateNormalizesDelayAndResetClearsAllKinds() {
    var gate = NotificationDeliveryRetryGate()
    let failedAt = Date(timeIntervalSince1970: 4_000)

    gate.markFailed(.highMemory, at: failedAt, retryDelay: .nan)
    XCTAssertFalse(gate.canAttempt(.highMemory, at: failedAt.addingTimeInterval(59)))
    XCTAssertTrue(gate.canAttempt(.highMemory, at: failedAt.addingTimeInterval(60)))

    for kind in AlertKind.allCases {
      gate.markFailed(kind, at: failedAt, retryDelay: .infinity)
    }
    XCTAssertEqual(gate.pendingCount, AlertKind.allCases.count)

    gate.reset()
    XCTAssertEqual(gate.pendingCount, 0)
  }
}
