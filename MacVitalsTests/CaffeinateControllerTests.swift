import Dispatch
import XCTest

@testable import MacVitals

@MainActor
final class CaffeinateControllerTests: XCTestCase {
  func testUsesSystemCaffeinateExecutable() {
    XCTAssertEqual(CaffeinateController.executablePath, "/usr/bin/caffeinate")
  }

  func testArgumentsPreventDisplayAndIdleSleepUntilMacVitalsExits() {
    XCTAssertEqual(
      CaffeinateController.arguments(parentProcessIdentifier: 4_242),
      ["-d", "-i", "-w", "4242"])
  }

  func testLaunchFailurePublishesErrorAndInactiveState() {
    let controller = CaffeinateController(
      executablePath: "/path/that/does/not/exist/macvitals-caffeinate-test")

    controller.start()

    XCTAssertFalse(controller.isActive)
    XCTAssertNotNil(controller.lastErrorDescription)
  }

  func testStopClearsActiveState() throws {
    let controller = CaffeinateController(
      executablePath: "/bin/sleep",
      argumentsProvider: { _ in ["5"] },
      processIdentifierProvider: { 1 })
    defer { controller.stop() }

    controller.start()
    XCTAssertTrue(controller.isActive)

    controller.stop()

    XCTAssertFalse(controller.isActive)
    XCTAssertNil(controller.lastErrorDescription)
  }

  func testUnexpectedChildExitClearsActiveState() async throws {
    let controller = CaffeinateController(
      executablePath: "/bin/sleep",
      argumentsProvider: { _ in ["0.1"] },
      processIdentifierProvider: { 1 })
    defer { controller.stop() }

    controller.start()
    XCTAssertTrue(controller.isActive)

    try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
      !controller.isActive
    }

    XCTAssertFalse(controller.isActive)
    XCTAssertNil(controller.lastErrorDescription)
  }

  private func waitUntil(
    timeoutNanoseconds: UInt64,
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let started = DispatchTime.now().uptimeNanoseconds
    while !condition() {
      let elapsed = DispatchTime.now().uptimeNanoseconds - started
      if elapsed >= timeoutNanoseconds {
        XCTFail("Timed out waiting for condition")
        return
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
  }
}
