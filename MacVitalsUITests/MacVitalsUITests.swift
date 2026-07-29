import Foundation
import XCTest

@MainActor
final class MacVitalsUITests: XCTestCase {
  func testPreferencesWindowLaunches() {
    assertPreferencesLaunch(
      language: "en",
      locale: "en_US",
      labels: .init(
        general: "General",
        alerts: "Alerts",
        menuBar: "Menu Bar",
        fans: "Fans",
        diagnostics: "Diagnostics",
        privacy: "Privacy"))
    assertPreferencesLaunch(
      language: "ru",
      locale: "ru_RU",
      labels: .init(
        general: "Основные",
        alerts: "Уведомления",
        menuBar: "Строка меню",
        fans: "Вентиляторы",
        diagnostics: "Диагностика",
        privacy: "Приватность"))

    for appearance in ["Light", "Dark"] {
      assertThemeLaunch(style: "duotone", appearance: appearance)
      assertThemeLaunch(style: "multicolor", appearance: appearance)
    }
  }

  private func assertPreferencesLaunch(
    language: String,
    locale: String,
    labels: TabLabels,
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
      "Preferences window did not open for \(language)",
      file: file,
      line: line)
    assertElementExists("colorSchemePicker", in: app, file: file, line: line)
    assertElementExists("themePreview.duotone", in: app, file: file, line: line)
    assertElementExists("themePreview.multicolor", in: app, file: file, line: line)

    selectTab(labels.general, language: language, in: app, file: file, line: line)
    assertElementExists("samplingIntervalPicker", in: app, file: file, line: line)
    assertElementExists("showInDockToggle", in: app, file: file, line: line)
    assertElementExists("launchAtLoginToggle", in: app, file: file, line: line)

    selectTab(labels.alerts, language: language, in: app, file: file, line: line)
    assertElementExists("notificationsEnabledToggle", in: app, file: file, line: line)
    assertElementExists("memoryAlertThresholdSlider", in: app, file: file, line: line)
    assertElementExists("lowBatteryAlertThresholdSlider", in: app, file: file, line: line)

    selectTab(labels.menuBar, language: language, in: app, file: file, line: line)
    assertElementExists("menuPresetPicker", in: app, file: file, line: line)
    assertElementExists("menuMetricLayoutList", in: app, file: file, line: line)
    assertElementExists("restoreDefaultsButton", in: app, file: file, line: line)

    selectTab(labels.fans, language: language, in: app, file: file, line: line)
    assertElementExists("fanControlStatus", in: app, file: file, line: line)
    assertElementExists("fanControlList", in: app, file: file, line: line)
    assertElementExists("fanControlSafetyNotice", in: app, file: file, line: line)

    selectTab(labels.diagnostics, language: language, in: app, file: file, line: line)
    assertElementExists("exportDiagnosticsButton", in: app, file: file, line: line)

    selectTab(labels.privacy, language: language, in: app, file: file, line: line)
    assertElementExists("privacyLocalOnlySummary", in: app, file: file, line: line)
    assertElementExists("privacySupportBundleSummary", in: app, file: file, line: line)

    app.terminate()
  }

  private func assertThemeLaunch(
    style: String,
    appearance: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let app = XCUIApplication()
    app.launchArguments = [
      "-AppleLanguages", "(en)",
      "-AppleLocale", "en_US",
      "-AppleInterfaceStyle", appearance,
      "-interfaceColorScheme", style,
    ]
    app.launch()
    app.typeKey(",", modifierFlags: .command)

    XCTAssertTrue(
      app.windows.firstMatch.waitForExistence(timeout: 5),
      "Preferences did not open for \(style) in \(appearance)",
      file: file,
      line: line)
    assertElementExists("colorSchemePicker", in: app, file: file, line: line)
    assertElementExists("themePreview.\(style)", in: app, file: file, line: line)

    app.terminate()
  }

  private func selectTab(
    _ localizedLabel: String,
    language: String,
    in app: XCUIApplication,
    file: StaticString,
    line: UInt
  ) {
    let predicate = NSPredicate(format: "label == %@", localizedLabel)
    let candidates = [
      app.radioButtons.matching(predicate).firstMatch,
      app.buttons.matching(predicate).firstMatch,
      app.descendants(matching: .any).matching(predicate).firstMatch,
    ]
    guard let element = candidates.first(where: { $0.waitForExistence(timeout: 1) }) else {
      XCTFail(
        "Missing localized tab label for \(language): \(localizedLabel)",
        file: file,
        line: line)
      return
    }
    element.click()
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

  private struct TabLabels {
    let general: String
    let alerts: String
    let menuBar: String
    let fans: String
    let diagnostics: String
    let privacy: String
  }
}
