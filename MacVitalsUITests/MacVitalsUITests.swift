import XCTest

@MainActor
final class MacVitalsUITests: XCTestCase {
  func testPreferencesWindowLaunches() {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launch()
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
  }
}
