import XCTest
@testable import MacVitals

final class SamplingIntervalPolicyTests: XCTestCase {
  func testNormalizesNonFiniteAndNonPositiveValuesToDefault() {
    XCTAssertEqual(SamplingIntervalPolicy.normalized(.nan), 5)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(.infinity), 5)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(-.infinity), 5)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(0), 5)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(-1), 5)
  }

  func testSupportsFastBalancedAndLowOverheadCadences() {
    XCTAssertEqual(SamplingIntervalPolicy.supportedValues, [1, 2, 5, 10, 15, 30])
    for value in SamplingIntervalPolicy.supportedValues {
      XCTAssertEqual(SamplingIntervalPolicy.normalized(value), value)
    }
  }

  func testUnsupportedValuesSnapToNearestSupportedCadence() {
    XCTAssertEqual(SamplingIntervalPolicy.normalized(0.5), 1)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(1.6), 2)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(3.5), 2)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(7), 5)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(12), 10)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(100), 30)
  }

  func testHistoryCapacityKeepsApproximatelyOneHour() {
    XCTAssertEqual(SamplingIntervalPolicy.historyCapacity(for: 1), 3_600)
    XCTAssertEqual(SamplingIntervalPolicy.historyCapacity(for: 5), 720)
    XCTAssertEqual(SamplingIntervalPolicy.historyCapacity(for: 30), 120)
  }

  func testSleepNanosecondsCannotTrapOnCorruptInputs() {
    XCTAssertEqual(
      SamplingIntervalPolicy.sleepNanoseconds(
        intervalSeconds: .infinity,
        elapsedMilliseconds: .infinity),
      5_000_000_000)
    XCTAssertEqual(
      SamplingIntervalPolicy.sleepNanoseconds(
        intervalSeconds: .nan,
        elapsedMilliseconds: .nan),
      5_000_000_000)
    XCTAssertEqual(
      SamplingIntervalPolicy.sleepNanoseconds(
        intervalSeconds: 5,
        elapsedMilliseconds: 1_000),
      4_000_000_000)
    XCTAssertEqual(
      SamplingIntervalPolicy.sleepNanoseconds(
        intervalSeconds: 2,
        elapsedMilliseconds: 500),
      1_500_000_000)
  }
  func testLegacyIntervalMigratesToBothPowerProfiles() {
    let preferences = SamplingIntervalPreferences.resolve(
      legacyValue: 10,
      batteryValue: nil,
      externalPowerValue: nil)

    XCTAssertEqual(preferences.onBattery, 10)
    XCTAssertEqual(preferences.onExternalPower, 10)
  }

  func testPowerSpecificIntervalsOverrideLegacyValueIndependently() {
    let preferences = SamplingIntervalPreferences.resolve(
      legacyValue: 5,
      batteryValue: 15,
      externalPowerValue: 2)

    XCTAssertEqual(preferences.interval(for: .battery), 15)
    XCTAssertEqual(preferences.interval(for: .externalPower), 2)
  }

  func testPowerSpecificIntervalsNormalizeCorruptValues() {
    let preferences = SamplingIntervalPreferences.resolve(
      legacyValue: 5,
      batteryValue: .infinity,
      externalPowerValue: 7)

    XCTAssertEqual(preferences.onBattery, SamplingIntervalPolicy.defaultValue)
    XCTAssertEqual(preferences.onExternalPower, 5)
  }

  func testPowerSourceResolutionPrefersExternalPowerSignals() {
    XCTAssertEqual(
      SamplingPowerSource.resolve(
        externalPowerConnected: true,
        adapterConnected: false,
        batteryPresent: true,
        fallback: .battery),
      .externalPower)
    XCTAssertEqual(
      SamplingPowerSource.resolve(
        externalPowerConnected: nil,
        adapterConnected: true,
        batteryPresent: true,
        fallback: .battery),
      .externalPower)
    XCTAssertEqual(
      SamplingPowerSource.resolve(
        externalPowerConnected: nil,
        adapterConnected: nil,
        batteryPresent: false,
        fallback: .battery),
      .externalPower)
  }

  func testPowerSourceResolutionUsesBatteryAndStableFallback() {
    XCTAssertEqual(
      SamplingPowerSource.resolve(
        externalPowerConnected: false,
        adapterConnected: false,
        batteryPresent: true,
        fallback: .externalPower),
      .battery)
    XCTAssertEqual(
      SamplingPowerSource.resolve(
        externalPowerConnected: nil,
        adapterConnected: nil,
        batteryPresent: nil,
        fallback: .battery),
      .battery)
  }

}
