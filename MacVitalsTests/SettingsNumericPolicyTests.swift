import XCTest
@testable import MacVitals

final class SettingsNumericPolicyTests: XCTestCase {
  func testMemoryThresholdUsesDefaultForCorruptValues() {
    XCTAssertEqual(SettingsNumericPolicy.memoryAlertThreshold(.nan), 90)
    XCTAssertEqual(SettingsNumericPolicy.memoryAlertThreshold(.infinity), 90)
    XCTAssertEqual(SettingsNumericPolicy.memoryAlertThreshold(-1), 90)
    XCTAssertEqual(SettingsNumericPolicy.memoryAlertThreshold(0), 90)
  }

  func testMemoryThresholdClampsFiniteValues() {
    XCTAssertEqual(SettingsNumericPolicy.memoryAlertThreshold(10), 50)
    XCTAssertEqual(SettingsNumericPolicy.memoryAlertThreshold(75), 75)
    XCTAssertEqual(SettingsNumericPolicy.memoryAlertThreshold(150), 100)
  }

  func testLowBatteryThresholdUsesDefaultForCorruptValues() {
    XCTAssertEqual(SettingsNumericPolicy.lowBatteryAlertThreshold(.nan), 15)
    XCTAssertEqual(SettingsNumericPolicy.lowBatteryAlertThreshold(.infinity), 15)
    XCTAssertEqual(SettingsNumericPolicy.lowBatteryAlertThreshold(-1), 15)
    XCTAssertEqual(SettingsNumericPolicy.lowBatteryAlertThreshold(0), 15)
  }

  func testLowBatteryThresholdClampsFiniteValues() {
    XCTAssertEqual(SettingsNumericPolicy.lowBatteryAlertThreshold(1), 5)
    XCTAssertEqual(SettingsNumericPolicy.lowBatteryAlertThreshold(20), 20)
    XCTAssertEqual(SettingsNumericPolicy.lowBatteryAlertThreshold(100), 50)
  }
}