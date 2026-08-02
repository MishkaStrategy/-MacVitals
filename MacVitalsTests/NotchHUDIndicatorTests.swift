import AppKit
import XCTest
@testable import MacVitals

final class NotchHUDIndicatorTests: XCTestCase {
  func testPanelFrameIsCenteredOnNotch() {
    var configuration = NotchHUDConfiguration.minimal
    configuration.horizontalExtension = 80

    let screen = NSRect(x: 0, y: 0, width: 1_512, height: 982)
    let frame = NotchHUDLayout.panelFrame(
      for: screen,
      safeAreaTop: 38,
      configuration: configuration)

    XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
    XCTAssertEqual(frame.width, 372, accuracy: 0.001)
    XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.001)
  }

  func testContourGeometryMatchesHardwareNotchWidth() {
    let geometry = NotchHUDLayout.contourGeometry(
      in: CGSize(width: 356, height: 68),
      safeAreaTop: 38)

    XCTAssertEqual(geometry.notchRightX - geometry.notchLeftX, 212, accuracy: 0.001)
    XCTAssertGreaterThan(geometry.bottomY, geometry.topY)
  }

  func testEmptySnapshotProducesUnavailableReading() {
    let reading = NotchHUDReadingResolver.resolve(
      snapshot: .empty,
      configuration: .minimal)

    XCTAssertNil(reading.numericValue)
    XCTAssertEqual(reading.displayValue, "—")
    XCTAssertEqual(reading.progress, 0)
    XCTAssertEqual(reading.level, .unavailable)
  }

  func testPersistenceRoundTripKeepsIndicatorAppearance() throws {
    var configuration = NotchHUDConfiguration.configuration(for: .battery)
    configuration.colorMode = .custom
    configuration.accent = .mint
    configuration.lineThickness = 4
    configuration.horizontalExtension = 120

    let data = try XCTUnwrap(NotchHUDConfigurationPersistence.encode(configuration))
    let restored = try XCTUnwrap(NotchHUDConfigurationPersistence.decode(data))

    XCTAssertEqual(restored, configuration)
  }

  func testBatteryThresholdOrderIsNormalizedForLowerIsWorse() {
    var configuration = NotchHUDConfiguration.configuration(for: .battery)
    configuration.warningThreshold = 10
    configuration.criticalThreshold = 25

    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    XCTAssertEqual(normalized.warningThreshold, 25)
    XCTAssertEqual(normalized.criticalThreshold, 10)
  }
}
