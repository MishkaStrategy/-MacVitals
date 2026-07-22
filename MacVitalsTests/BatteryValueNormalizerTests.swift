import XCTest
@testable import MacVitals

final class BatteryValueNormalizerTests: XCTestCase {
  func testFiniteNumberRejectsMissingAndNonFiniteValues() {
    XCTAssertNil(BatteryValueNormalizer.finiteNumber(nil))
    XCTAssertNil(BatteryValueNormalizer.finiteNumber("12"))
    XCTAssertNil(BatteryValueNormalizer.finiteNumber(NSNumber(value: Double.nan)))
    XCTAssertNil(BatteryValueNormalizer.finiteNumber(NSNumber(value: Double.infinity)))
    XCTAssertEqual(BatteryValueNormalizer.finiteNumber(NSNumber(value: 12.5)), 12.5)
  }

  func testPercentageRequiresBothValidCapacities() {
    XCTAssertNil(BatteryValueNormalizer.percentage(current: nil, maximum: 100))
    XCTAssertNil(BatteryValueNormalizer.percentage(current: 50, maximum: nil))
    XCTAssertNil(BatteryValueNormalizer.percentage(current: -1, maximum: 100))
    XCTAssertNil(BatteryValueNormalizer.percentage(current: 50, maximum: 0))
    XCTAssertEqual(
      BatteryValueNormalizer.percentage(current: 50, maximum: 100),
      50)
    XCTAssertEqual(
      BatteryValueNormalizer.percentage(current: 120, maximum: 100),
      100)
  }

  func testCapacityHealthAndCycleBounds() {
    XCTAssertEqual(BatteryValueNormalizer.capacityMah(6_000), 6_000)
    XCTAssertNil(BatteryValueNormalizer.capacityMah(-1))
    XCTAssertNil(BatteryValueNormalizer.capacityMah(100_001))
    XCTAssertEqual(
      BatteryValueNormalizer.healthPercent(maximumMah: 4_500, designMah: 5_000),
      90)
    XCTAssertNil(BatteryValueNormalizer.healthPercent(maximumMah: 4_500, designMah: 0))
    XCTAssertEqual(BatteryValueNormalizer.cycleCount(NSNumber(value: 321)), 321)
    XCTAssertNil(BatteryValueNormalizer.cycleCount(NSNumber(value: -1)))
    XCTAssertNil(BatteryValueNormalizer.cycleCount(NSNumber(value: 2.5)))
  }

  func testTemperatureElectricalConversionsAndSignedPower() {
    XCTAssertEqual(BatteryValueNormalizer.temperatureCelsius(raw: 2_950), 29.5)
    XCTAssertEqual(BatteryValueNormalizer.temperatureCelsius(raw: 35), 35)
    XCTAssertNil(BatteryValueNormalizer.temperatureCelsius(raw: 20_000))
    XCTAssertEqual(BatteryValueNormalizer.millivoltsToVolts(12_000), 12)
    XCTAssertNil(BatteryValueNormalizer.millivoltsToVolts(40_000))
    XCTAssertEqual(BatteryValueNormalizer.milliampsToAmps(-2_000), -2)
    XCTAssertNil(BatteryValueNormalizer.milliampsToAmps(40_000))
    XCTAssertEqual(
      BatteryValueNormalizer.powerWatts(voltage: 12, current: -2),
      -24)
    XCTAssertNil(BatteryValueNormalizer.powerWatts(voltage: nil, current: 2))
  }

  func testMinutesTextAndBatteryState() {
    XCTAssertEqual(BatteryValueNormalizer.validMinutes(120), 120)
    XCTAssertNil(BatteryValueNormalizer.validMinutes(-1))
    XCTAssertNil(BatteryValueNormalizer.validMinutes(100_000))
    XCTAssertEqual(BatteryValueNormalizer.text("  Good  "), "Good")
    XCTAssertNil(BatteryValueNormalizer.text("   "))
    XCTAssertEqual(
      BatteryValueNormalizer.state(charging: true, externalPower: true, percentage: 50),
      .charging)
    XCTAssertEqual(
      BatteryValueNormalizer.state(charging: false, externalPower: true, percentage: 100),
      .charged)
    XCTAssertEqual(
      BatteryValueNormalizer.state(charging: false, externalPower: true, percentage: 50),
      .adapterPower)
    XCTAssertEqual(
      BatteryValueNormalizer.state(charging: false, externalPower: false, percentage: 50),
      .discharging)
  }
}
