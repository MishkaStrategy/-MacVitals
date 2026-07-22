import XCTest

@MainActor
final class MacVitalsUITests: XCTestCase {
  func testPreferencesWindowLaunches() {
    assertPreferencesLaunch(
      language: "en",
      locale: "en_US",
      localizedGeneralLabel: "General")
    assertPreferencesLaunch(
      language: "ru",
      locale: "ru_RU",
      localizedGeneralLabel: "Основные")
  }

  private func assertPreferencesLaunch(
    language: String,
    locale: String,
    localizedGeneralLabel: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let app = XCUIApplication()
    app.launchArguments = [
      "-AppleLanguages", "(\(language))",
      "-AppleLocale", locale,
    ]
    app.launch()
    app.typeKey(",", modifierFlags: .command)

    XCTAssertTrue(
      app.windows.firstMatch.waitForExistence(timeout: 5),
      "Preferences window did not open for \(language)",
      file: file,
      line: line)
    assertElementExists("samplingIntervalPicker", in: app, file: file, line: line)
    assertElementExists("showInDockToggle", in: app, file: file, line: line)
    assertElementExists("launchAtLoginToggle", in: app, file: file, line: line)
    assertElementExists("reduceMotionToggle", in: app, file: file, line: line)

    let localizedLabel = app.descendants(matching: .any)[localizedGeneralLabel]
    XCTAssertTrue(
      localizedLabel.waitForExistence(timeout: 3),
      "Missing localized General label for \(language): \(localizedGeneralLabel)",
      file: file,
      line: line)

    app.terminate()
  }

  private func assertElementExists(
    _ identifier: String,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    XCTAssertTrue(
      element.waitForExistence(timeout: 3),
      "Missing accessibility element: \(identifier)",
      file: file,
      line: line)
  }
}
