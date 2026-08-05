import XCTest

@MainActor
final class ReadmeStatusAndHUDScreenshotTests: XCTestCase {
  func testCaptureStatusBarAndHUDScreenshots() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-AppleLanguages", "(ru)",
      "-AppleLocale", "ru_RU",
      "-AppleInterfaceStyle", "Dark",
      "-interfaceColorScheme", "multicolor",
      "-experimentalNotchHUDEnabled", "YES",
    ]
    app.launch()

    guard let statusItem = findStatusItem(in: app) else {
      XCTFail("MacVitals status item did not appear for README screenshot capture")
      app.terminate()
      return
    }

    Thread.sleep(forTimeInterval: 2)
    statusItem.click()
    XCTAssertTrue(
      app.staticTexts["MacVitals"].firstMatch.waitForExistence(timeout: 5),
      "MacVitals overview popover did not open for README screenshot capture")
    Thread.sleep(forTimeInterval: 0.5)
    captureScreenScreenshot(named: "status-bar-overview")

    statusItem.click()
    Thread.sleep(forTimeInterval: 0.4)
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(
      app.windows.firstMatch.waitForExistence(timeout: 5),
      "Preferences window did not open for HUD screenshot capture")

    selectTab("Индикатор выреза", in: app)
    ensureToggle(identifier: "notchHUDEnabledToggle", isOn: true, in: app)
    ensureToggle(
      label: "Показывать имитацию контура на экранах без выреза",
      isOn: true,
      in: app)

    app.typeKey("w", modifierFlags: .command)
    Thread.sleep(forTimeInterval: 1)
    captureScreenScreenshot(named: "notch-hud")

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

  private func selectTab(
    _ localizedLabel: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let predicate = NSPredicate(format: "label == %@", localizedLabel)
    let candidates = [
      app.radioButtons.matching(predicate).firstMatch,
      app.buttons.matching(predicate).firstMatch,
      app.descendants(matching: .any).matching(predicate).firstMatch,
    ]
    guard let element = candidates.first(where: { $0.waitForExistence(timeout: 1) }) else {
      XCTFail("Missing Preferences tab: \(localizedLabel)", file: file, line: line)
      return
    }
    element.click()
    Thread.sleep(forTimeInterval: 0.3)
  }

  private func ensureToggle(
    identifier: String,
    isOn expectedState: Bool,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let candidates = [
      app.switches.matching(identifier: identifier).firstMatch,
      app.checkBoxes.matching(identifier: identifier).firstMatch,
      app.descendants(matching: .any).matching(identifier: identifier).firstMatch,
    ]
    guard let toggle = candidates.first(where: { $0.waitForExistence(timeout: 2) }) else {
      XCTFail("Missing toggle identifier: \(identifier)", file: file, line: line)
      return
    }
    setToggle(toggle, isOn: expectedState)
  }

  private func ensureToggle(
    label: String,
    isOn expectedState: Bool,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let predicate = NSPredicate(format: "label == %@", label)
    let candidates = [
      app.switches.matching(predicate).firstMatch,
      app.checkBoxes.matching(predicate).firstMatch,
      app.buttons.matching(predicate).firstMatch,
      app.descendants(matching: .any).matching(predicate).firstMatch,
    ]
    guard let toggle = candidates.first(where: { $0.waitForExistence(timeout: 2) }) else {
      XCTFail("Missing toggle label: \(label)", file: file, line: line)
      return
    }
    setToggle(toggle, isOn: expectedState)
  }

  private func setToggle(_ toggle: XCUIElement, isOn expectedState: Bool) {
    let currentState = toggleState(toggle)
    if currentState != expectedState {
      toggle.click()
      Thread.sleep(forTimeInterval: 0.4)
    }
  }

  private func toggleState(_ toggle: XCUIElement) -> Bool {
    let value = String(describing: toggle.value ?? "").lowercased()
    return value == "1" || value == "true" || value == "on" || value == "selected"
  }

  private func captureScreenScreenshot(named name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "\(name).png"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
