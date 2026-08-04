import XCTest
@testable import MacVitals

final class NotchHUDCompactDefaultsTests: XCTestCase {
  func testDefaultConfigurationUsesOneCPUSensor() {
    let configuration = NotchHUDConfigurationPolicy.normalized(.minimal)

    XCTAssertEqual(configuration.metric, .cpu)
    XCTAssertNil(configuration.secondaryMetric)
    XCTAssertEqual(configuration.indicatorCount, .one)
    XCTAssertTrue(configuration.showValueText)
    XCTAssertTrue(configuration.showSensorName)
    XCTAssertEqual(configuration.colorMode, .automatic)
    XCTAssertEqual(configuration.lineThickness, 2.5)
    XCTAssertFalse(configuration.showOnDisplaysWithoutNotch)
  }

  func testEnablingTwoIndicatorsAddsTemperatureOnTheRight() {
    let changed = NotchHUDConfigurationPolicy.settingIndicatorCount(
      .two,
      in: .minimal)

    XCTAssertEqual(changed.metric, .cpu)
    XCTAssertEqual(changed.secondaryMetric, .temperature)
    XCTAssertEqual(changed.indicatorCount, .two)
    XCTAssertEqual(changed.secondaryWarningThreshold, 75)
    XCTAssertEqual(changed.secondaryCriticalThreshold, 90)
  }

  func testReturningToOneIndicatorRemovesOnlySecondaryState() {
    let dual = NotchHUDConfigurationPolicy.settingIndicatorCount(.two, in: .minimal)
    let single = NotchHUDConfigurationPolicy.settingIndicatorCount(.one, in: dual)

    XCTAssertEqual(single.metric, .cpu)
    XCTAssertNil(single.secondaryMetric)
    XCTAssertNil(single.secondaryWarningThreshold)
    XCTAssertNil(single.secondaryCriticalThreshold)
    XCTAssertEqual(single.indicatorCount, .one)
  }

  func testChangingPrimarySensorResetsItsThresholds() {
    let changed = NotchHUDConfigurationPolicy.setting(
      .battery,
      side: .left,
      in: .minimal)

    XCTAssertEqual(changed.metric, .battery)
    XCTAssertEqual(changed.warningThreshold, 25)
    XCTAssertEqual(changed.criticalThreshold, 10)
  }

  func testDuplicateSecondarySensorIsReplaced() {
    var configuration = NotchHUDConfigurationPolicy.settingIndicatorCount(.two, in: .minimal)
    configuration.secondaryMetric = .cpu

    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    XCTAssertNotEqual(normalized.secondaryMetric, normalized.metric)
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
    XCTAssertNil(migrated.secondaryMetric)
    XCTAssertEqual(migrated.indicatorCount, .one)
    XCTAssertEqual(migrated.warningThreshold, 75)
    XCTAssertEqual(migrated.criticalThreshold, 90)
  }
}
