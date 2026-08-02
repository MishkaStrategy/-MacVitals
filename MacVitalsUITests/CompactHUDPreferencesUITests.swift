import XCTest

@MainActor
final class CompactHUDPreferencesUITests: XCTestCase {
  func testCompactHUDPreferencesAreIntegrated() {
    assertIntegratedHUD(language: "en", locale: "en_US", tabLabel: "Around Status Bar")
    assertIntegratedHUD(language: "ru", locale: "ru_RU", tabLabel: "Вокруг строки меню")
  }

  private func assertIntegratedHUD(
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
      XCTFail("Missing HUD tab for \(language): \(tabLabel)", file: file, line: line)
      app.terminate()
      return
    }
    tab.click()

    for identifier in [
      "notchHUDIntegratedSettings",
      "notchHUDEnabledToggle",
      "notchHUDLivePreview",
      "notchHUDPresetPicker",
      "notchHUDTileSelector.cpu",
      "notchHUDVisibleCount.left",
      "notchHUDVisibleCount.right",
    ] {
      let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
      XCTAssertTrue(
        element.waitForExistence(timeout: 3),
        "Missing compact HUD element for \(language): \(identifier)",
        file: file,
        line: line)
    }

    app.terminate()
  }
}
