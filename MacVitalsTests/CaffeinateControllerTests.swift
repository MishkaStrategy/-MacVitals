import XCTest
@testable import MacVitals

final class CaffeinateControllerTests: XCTestCase {
  func testUsesSystemCaffeinateExecutable() {
    XCTAssertEqual(CaffeinateController.executablePath, "/usr/bin/caffeinate")
  }

  func testArgumentsPreventDisplayAndIdleSleepUntilMacVitalsExits() {
    XCTAssertEqual(
      CaffeinateController.arguments(parentProcessIdentifier: 4_242),
      ["-d", "-i", "-w", "4242"])
  }
}
