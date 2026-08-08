import Foundation
import XCTest

@MainActor
final class SharedProcessSamplingValidationUITests: XCTestCase {
  func testPrimaryCPUConsumerAndHistoricalCenterRunTogether() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_US",
      "-samplingInterval", "1",
      "-notificationsEnabled", "NO",
      "-showInDock", "NO",
    ]
    app.launch()

    guard let statusItem = findStatusItem(in: app) else {
      XCTFail("MacVitals status item did not appear for shared process sampling validation")
      app.terminate()
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
    ]
    guard let cpuButton = cpuCandidates.first(where: { $0.waitForExistence(timeout: 2) }) else {
      XCTFail("CPU metric button did not appear")
      app.terminate()
      return
    }
    cpuButton.click()

    let processConsumers = app.descendants(matching: .any)
      .matching(identifier: "processConsumers.cpu")
      .firstMatch
    XCTAssertTrue(
      processConsumers.waitForExistence(timeout: 8),
      "Primary CPU process consumer did not appear")

    try writeMarker(
      environmentKey: "MACVITALS_SHARED_SAMPLING_READY_FILE",
      value: "ready\n")

    Thread.sleep(forTimeInterval: 70)
    XCTAssertTrue(
      processConsumers.exists,
      "Primary CPU process consumer disappeared during validation")

    let historyLabel = "Consumption leaders"
    let historyPredicate = NSPredicate(format: "label == %@", historyLabel)
    let historyCandidates = [
      app.radioButtons.matching(historyPredicate).firstMatch,
      app.buttons.matching(historyPredicate).firstMatch,
      app.descendants(matching: .any).matching(historyPredicate).firstMatch,
    ]
    guard let historyTab = historyCandidates.first(where: { $0.waitForExistence(timeout: 2) }) else {
      XCTFail("Historical consumption tab did not appear")
      app.terminate()
      return
    }
    historyTab.click()

    XCTAssertTrue(
      app.staticTexts["Top applications"].firstMatch.waitForExistence(timeout: 5),
      "Historical consumption leaders did not become visible")
    XCTAssertFalse(
      app.staticTexts["Collecting historical activity"].firstMatch.exists,
      "Historical center did not publish activity after the multi-consumer interval")

    try writeMarker(
      environmentKey: "MACVITALS_SHARED_SAMPLING_COMPLETE_FILE",
      value: "history-visible\n")
    app.terminate()
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

  private func writeMarker(environmentKey: String, value: String) throws {
    guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
      XCTFail("Missing validation marker environment: \(environmentKey)")
      return
    }
    let url = URL(fileURLWithPath: path)
    try Data(value.utf8).write(to: url, options: .atomic)
  }
}
