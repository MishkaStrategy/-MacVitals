import XCTest

@MainActor
final class MacVitalsUITests: XCTestCase {
  func testPreferencesWindowLaunches() {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launch()
    app.typeKey(",", modifierFlags: .command)

    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
    assertElementExists("samplingIntervalPicker", in: app)
    assertElementExists("showInDockToggle", in: app)
    assertElementExists("launchAtLoginToggle", in: app)
    assertElementExists("reduceMotionToggle", in: app)
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
