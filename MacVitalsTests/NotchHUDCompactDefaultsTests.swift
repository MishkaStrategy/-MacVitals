import XCTest
@testable import MacVitals

final class NotchHUDCompactDefaultsTests: XCTestCase {
  func testMinimalPresetUsesOneTilePerSide() {
    let configuration = NotchHUDConfigurationPolicy.normalized(.minimal)

    XCTAssertEqual(configuration.leftMetrics, [.cpu])
    XCTAssertEqual(configuration.rightMetrics, [.temperature])
    XCTAssertEqual(configuration.leftVisibleCount, 1)
    XCTAssertEqual(configuration.rightVisibleCount, 1)
    XCTAssertEqual(configuration.metrics(for: .left), [.cpu])
    XCTAssertEqual(configuration.metrics(for: .right), [.temperature])
    XCTAssertEqual(configuration.density, .compact)
    XCTAssertEqual(configuration.textSize, .small)
    XCTAssertFalse(configuration.showLabels)
    XCTAssertFalse(configuration.showSeparators)
  }

  func testMinimalPresetResolvesWithoutBecomingCustom() {
    XCTAssertEqual(
      NotchHUDConfigurationPolicy.resolvedPreset(for: .minimal),
      .minimal)
  }

  func testCustomPresetFallsBackToCompactConfiguration() {
    XCTAssertEqual(NotchHUDPreset.custom.configuration, .minimal)
  }
}
