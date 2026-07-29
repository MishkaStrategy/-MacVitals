import ServiceManagement
import XCTest
@testable import MacVitals

final class LaunchAtLoginManagerTests: XCTestCase {
  func testSystemStatusesMapToUserFacingStates() {
    XCTAssertEqual(LaunchAtLoginStateMapper.state(for: .notRegistered), .disabled)
    XCTAssertEqual(LaunchAtLoginStateMapper.state(for: .enabled), .enabled)
    XCTAssertEqual(LaunchAtLoginStateMapper.state(for: .requiresApproval), .requiresApproval)
    XCTAssertEqual(LaunchAtLoginStateMapper.state(for: .notFound), .unavailable)
  }

  func testOnlyEnabledStateReportsEnabled() {
    XCTAssertTrue(LaunchAtLoginState.enabled.isEnabled)
    XCTAssertFalse(LaunchAtLoginState.disabled.isEnabled)
    XCTAssertFalse(LaunchAtLoginState.requiresApproval.isEnabled)
    XCTAssertFalse(LaunchAtLoginState.unavailable.isEnabled)
    XCTAssertFalse(LaunchAtLoginState.failed("failure").isEnabled)
  }

  func testActionableStatesExposeMessages() {
    XCTAssertNil(LaunchAtLoginState.enabled.message)
    XCTAssertNil(LaunchAtLoginState.disabled.message)
    XCTAssertNotNil(LaunchAtLoginState.requiresApproval.message)
    XCTAssertNotNil(LaunchAtLoginState.unavailable.message)
    XCTAssertEqual(LaunchAtLoginState.failed("failure").message, "failure")
  }
}
