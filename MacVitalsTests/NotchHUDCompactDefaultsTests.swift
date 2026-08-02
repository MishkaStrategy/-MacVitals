import XCTest
@testable import MacVitals

final class NotchHUDCompactDefaultsTests: XCTestCase {
  func testDefaultConfigurationUsesOneCPUSensor() {
    let configuration = NotchHUDConfigurationPolicy.normalized(.minimal)

    XCTAssertEqual(configuration.metric, .cpu)
    XCTAssertTrue(configuration.showValueText)
    XCTAssertTrue(configuration.showSensorName)
    XCTAssertEqual(configuration.colorMode, .automatic)
    XCTAssertEqual(configuration.lineThickness, 2.5)
    XCTAssertFalse(configuration.showOnDisplaysWithoutNotch)
  }

  func testChangingSensorResetsItsThresholds() {
    let changed = NotchHUDConfigurationPolicy.setting(
      .battery,
      side: nil,
      in: .minimal)

    XCTAssertEqual(changed.metric, .battery)
    XCTAssertEqual(changed.warningThreshold, 25)
    XCTAssertEqual(changed.criticalThreshold, 10)
  }

  func testLegacyTileConfigurationMigratesToSingleSensor() throws {
    let data = Data(
      """
      {
        "schemaVersion": 2,
        "configuration": {
          "leftMetrics": ["temperature", "cpu"],
          "rightMetrics": ["battery"]
        }
      }
      """.utf8)

    let migrated = try XCTUnwrap(NotchHUDConfigurationPersistence.decode(data))
    XCTAssertEqual(migrated.metric, .temperature)
    XCTAssertEqual(migrated.warningThreshold, 75)
    XCTAssertEqual(migrated.criticalThreshold, 90)
  }
}
