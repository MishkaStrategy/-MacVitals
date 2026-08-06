import XCTest

@testable import MacVitals

final class AutonomousSamplingPolicyTests: XCTestCase {
  func testAllowsNormalApplicationRuntime() {
    XCTAssertTrue(
      AutonomousSamplingPolicy.isEnabled(
        environment: [:],
        arguments: ["/Applications/MacVitals.app/Contents/MacOS/MacVitals"]))
  }

  func testRejectsXCTestConfigurationEnvironment() {
    XCTAssertFalse(
      AutonomousSamplingPolicy.isEnabled(
        environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"],
        arguments: ["MacVitals"]))
  }

  func testRejectsInjectedTestBundleEnvironment() {
    XCTAssertFalse(
      AutonomousSamplingPolicy.isEnabled(
        environment: ["XCInjectBundleInto": "/tmp/MacVitals"],
        arguments: ["MacVitals"]))
  }

  func testRejectsXCTestArgument() {
    XCTAssertFalse(
      AutonomousSamplingPolicy.isEnabled(
        environment: [:],
        arguments: ["MacVitals", "/tmp/MacVitalsTests.xctest"]))
  }

  func testExplicitDisableWinsInNormalRuntime() {
    XCTAssertFalse(
      AutonomousSamplingPolicy.isEnabled(
        environment: ["MACVITALS_DISABLE_AUTONOMOUS_SAMPLING": "1"],
        arguments: ["MacVitals"]))
  }
}
