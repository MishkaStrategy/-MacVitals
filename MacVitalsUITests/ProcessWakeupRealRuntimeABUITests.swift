import Foundation
import XCTest

@MainActor
final class ProcessWakeupRealRuntimeABUITests: XCTestCase {
  func testExposeCPUDetailForExternalMeasurement() throws {
    let environment = ProcessInfo.processInfo.environment
    guard
      let readyPath = environment["MACVITALS_REAL_AB_READY_FILE"], !readyPath.isEmpty,
      let stopPath = environment["MACVITALS_REAL_AB_STOP_FILE"], !stopPath.isEmpty,
      let completePath = environment["MACVITALS_REAL_AB_COMPLETE_FILE"], !completePath.isEmpty
    else {
      throw XCTSkip("Real-runtime wakeup A/B marker paths are required")
    }

    let app = XCUIApplication(bundleIdentifier: "com.mishkacher.MacVitals")
    app.activate()

    XCTAssertTrue(
      waitUntil(timeout: 10) { app.state == .runningForeground || app.state == .runningBackground },
      "Externally launched MacVitals did not become attachable")

    guard let statusItem = findStatusItem(in: app) else {
      XCTFail("MacVitals status item did not appear")
      return
    }
    statusItem.click()

    XCTAssertTrue(
      app.staticTexts["MacVitals"].firstMatch.waitForExistence(timeout: 5),
      "MacVitals overview popover did not open")

    let cpuPredicate = NSPredicate(format: "label BEGINSWITH %@", "CPU")
    let cpuCandidates = [
      app.buttons.matching(cpuPredicate).firstMatch,
      app.descendants(matching: .button).matching(cpuPredicate).firstMatch,
      app.staticTexts["CPU"].firstMatch,
    ]
    guard let cpuControl = cpuCandidates.first(where: { $0.waitForExistence(timeout: 2) }) else {
      XCTFail("CPU metric control did not appear in overview")
      return
    }
    cpuControl.click()

    let processConsumers = app.descendants(matching: .any)
      .matching(identifier: "processConsumers.cpu")
      .firstMatch
    XCTAssertTrue(
      processConsumers.waitForExistence(timeout: 15),
      "CPU process-consumer detail did not become visible")

    try Data("cpu-detail-active\n".utf8).write(
      to: URL(fileURLWithPath: readyPath),
      options: .atomic)

    XCTAssertTrue(
      waitUntil(timeout: 90) { FileManager.default.fileExists(atPath: stopPath) },
      "External measurement did not provide a stop marker")

    app.terminate()
    XCTAssertTrue(
      waitUntil(timeout: 12) { app.state == .notRunning },
      "MacVitals did not terminate after the external measurement")

    try Data("cpu-detail-complete\n".utf8).write(
      to: URL(fileURLWithPath: completePath),
      options: .atomic)
  }

  private func findStatusItem(in app: XCUIApplication) -> XCUIElement? {
    let labelPredicate = NSPredicate(format: "label == %@", "MacVitals")
    let candidates = [
      app.statusItems.matching(identifier: "macVitalsStatusItem").firstMatch,
      app.menuBars.statusItems.matching(identifier: "macVitalsStatusItem").firstMatch,
      app.descendants(matching: .statusItem)
        .matching(identifier: "macVitalsStatusItem").firstMatch,
      app.statusItems.matching(labelPredicate).firstMatch,
      app.menuBars.statusItems.matching(labelPredicate).firstMatch,
      app.descendants(matching: .statusItem).matching(labelPredicate).firstMatch,
    ]
    return candidates.first { $0.waitForExistence(timeout: 2) }
  }

  private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      Thread.sleep(forTimeInterval: 0.1)
    }
    return condition()
  }
}
