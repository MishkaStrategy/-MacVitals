import XCTest

@MainActor
final class CompactHUDPreferencesUITests: XCTestCase {
  func testNotchIndicatorPreferencesAreIntegrated() {
    assertIntegratedIndicator(language: "en", locale: "en_US", tabLabel: "Notch Indicator")
    assertIntegratedIndicator(language: "ru", locale: "ru_RU", tabLabel: "Индикатор выреза")
  }

  private func assertIntegratedIndicator(
    language: String,
    locale: String,
    tabLabel: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let app = XCUIApplication()
    app.launchArguments = [
      "-AppleLanguages", "(\(language))",
      "-AppleLocale", locale,
      "-interfaceColorScheme", "duotone",
    ]
    app.launch()
    app.typeKey(",", modifierFlags: .command)

    XCTAssertTrue(
      app.windows.firstMatch.waitForExistence(timeout: 5),
      "Preferences did not open for \(language)",
      file: file,
      line: line)

    let predicate = NSPredicate(format: "label == %@", tabLabel)
    let candidates = [
      app.radioButtons.matching(predicate).firstMatch,
      app.buttons.matching(predicate).firstMatch,
      app.descendants(matching: .any).matching(predicate).firstMatch,
    ]
    guard let tab = candidates.first(where: { $0.waitForExistence(timeout: 1) }) else {
      XCTFail("Missing notch indicator tab for \(language): \(tabLabel)", file: file, line: line)
      app.terminate()
      return
    }
    tab.click()

    for identifier in [
      "notchHUDIntegratedSettings",
      "notchHUDEnabledToggle",
      "notchHUDLivePreview",
      "notchIndicatorMetricPicker",
      "notchIndicatorShowValueToggle",
      "notchIndicatorLineThicknessSlider",
      "notchIndicatorWarningField",
      "notchIndicatorCriticalField",
    ] {
      let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
      XCTAssertTrue(
        element.waitForExistence(timeout: 3),
        "Missing notch indicator element for \(language): \(identifier)",
        file: file,
        line: line)
    }

    app.terminate()
  }
}
