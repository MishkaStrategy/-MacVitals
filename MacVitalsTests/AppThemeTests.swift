import XCTest
@testable import MacVitals

@MainActor
final class AppThemeTests: XCTestCase {
  func testThemeControllerPersistsSelectedScheme() {
    let suiteName = "AppThemeTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated defaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let key = "theme"
    let controller = ThemeController(defaults: defaults, key: key)
    XCTAssertEqual(controller.style, .duotone)

    controller.style = .multicolor

    let restored = ThemeController(defaults: defaults, key: key)
    XCTAssertEqual(restored.style, .multicolor)
  }

  func testInvalidStoredSchemeFallsBackToDuotone() {
    let suiteName = "AppThemeTests.invalid.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      return XCTFail("Could not create isolated defaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set("future-unknown-skin", forKey: "theme")
    let controller = ThemeController(defaults: defaults, key: "theme")

    XCTAssertEqual(controller.style, .duotone)
  }

  func testDuotoneUsesBlueForAllAvailableMetrics() {
    let palette = ThemePalette(style: .duotone)
    let metrics: [MetricKind] = [
      .cpu, .memory, .gpu, .battery, .systemPower, .temperature, .fans,
    ]

    for metric in metrics {
      XCTAssertEqual(palette.token(for: metric), .blue, "Unexpected token for \(metric)")
    }
    XCTAssertEqual(palette.token(for: .neutral), .gray)
  }

  func testMulticolorMetricMapping() {
    let palette = ThemePalette(style: .multicolor)

    XCTAssertEqual(palette.token(for: .cpu), .blue)
    XCTAssertEqual(palette.token(for: .memory), .purple)
    XCTAssertEqual(palette.token(for: .gpu), .green)
    XCTAssertEqual(palette.token(for: .battery), .mint)
    XCTAssertEqual(palette.token(for: .systemPower), .orange)
    XCTAssertEqual(palette.token(for: .temperature), .redOrange)
    XCTAssertEqual(palette.token(for: .fans), .cyan)
    XCTAssertEqual(palette.token(for: .neutral), .gray)
  }
}
