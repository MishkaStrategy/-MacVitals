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
}
