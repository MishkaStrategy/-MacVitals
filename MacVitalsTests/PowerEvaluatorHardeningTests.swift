import XCTest
@testable import MacVitals

final class PowerEvaluatorHardeningTests: XCTestCase {
  func testConfigurationNormalizesNonFiniteValues() {
    let configuration = ChargerSufficiencyConfiguration(
      insufficientDischargeWatts: .nan,
      borderlineDischargeWatts: .infinity,
      hysteresisWatts: -.infinity,
      confirmationDuration: .nan,
      minimumSamples: 0,
      maximumTimestampSkew: .infinity,
      maximumPlausibleBatteryPowerWatts: .nan,
      maximumPlausibleAdapterPowerWatts: .infinity)

    XCTAssertEqual(
      configuration.insufficientDischargeWatts,
      ChargerSufficiencyConfiguration.defaultInsufficientDischargeWatts)
    XCTAssertEqual(
      configuration.borderlineDischargeWatts,
      ChargerSufficiencyConfiguration.defaultBorderlineDischargeWatts)
    XCTAssertEqual(
      configuration.hysteresisWatts,
      ChargerSufficiencyConfiguration.defaultHysteresisWatts)
    XCTAssertEqual(
      configuration.confirmationDuration,
      ChargerSufficiencyConfiguration.defaultConfirmationDuration)
    XCTAssertEqual(configuration.minimumSamples, 1)
    XCTAssertEqual(
      configuration.maximumTimestampSkew,
      ChargerSufficiencyConfiguration.defaultMaximumTimestampSkew)
    XCTAssertEqual(
      configuration.maximumPlausibleBatteryPowerWatts,
      ChargerSufficiencyConfiguration.defaultMaximumPlausibleBatteryPowerWatts)
    XCTAssertEqual(
      configuration.maximumPlausibleAdapterPowerWatts,
      ChargerSufficiencyConfiguration.defaultMaximumPlausibleAdapterPowerWatts)
  }

  func testInvalidBatterySampleClearsEvidenceWindow() {
    var evaluator = ChargerSufficiencyEvaluator(
      configuration: .init(confirmationDuration: 4, minimumSamples: 2))
    let start = Date(timeIntervalSince1970: 1_000)

    XCTAssertEqual(
      evaluator.evaluate(sample(at: start, batteryPower: -4)).status,
      .unknown)
    XCTAssertEqual(evaluator.samples.count, 1)

    let conflict = evaluator.evaluate(
      sample(at: start.addingTimeInterval(2), batteryPower: .nan))
    XCTAssertEqual(conflict.status, .sensorConflict)
    XCTAssertTrue(evaluator.samples.isEmpty)

    XCTAssertEqual(
      evaluator.evaluate(
        sample(at: start.addingTimeInterval(4), batteryPower: -4)
      ).status,
      .unknown)
    XCTAssertEqual(
      evaluator.evaluate(
        sample(at: start.addingTimeInterval(8), batteryPower: -4)
      ).status,
      .insufficient)
  }

  func testInvalidAdapterPowerDoesNotEnterEvidenceWindow() {
    var evaluator = ChargerSufficiencyEvaluator(
      configuration: .init(confirmationDuration: 0, minimumSamples: 1))

    let result = evaluator.evaluate(
      PowerSample(
        timestamp: Date(timeIntervalSince1970: 1_000),
        externalPower: true,
        batteryPowerWatts: -4,
        adapterRatedPowerWatts: .infinity,
        adapterMeasuredPowerWatts: Double.greatestFiniteMagnitude,
        batteryPercent: 50))

    XCTAssertEqual(result.status, .sensorConflict)
    XCTAssertNil(result.estimatedSystemPowerWatts)
    XCTAssertTrue(evaluator.samples.isEmpty)
  }

  func testConfigurationClampsExtremeFiniteValues() {
    let configuration = ChargerSufficiencyConfiguration(
      insufficientDischargeWatts: 100_000,
      borderlineDischargeWatts: 100_000,
      hysteresisWatts: 100_000,
      confirmationDuration: 1_000_000,
      minimumSamples: Int.max,
      maximumTimestampSkew: 100_000,
      maximumPlausibleBatteryPowerWatts: 100_000,
      maximumPlausibleAdapterPowerWatts: 1_000_000)

    XCTAssertEqual(configuration.insufficientDischargeWatts, 10_000)
    XCTAssertEqual(configuration.borderlineDischargeWatts, 10_000)
    XCTAssertEqual(configuration.hysteresisWatts, 10_000)
    XCTAssertEqual(configuration.confirmationDuration, 86_400)
    XCTAssertEqual(configuration.minimumSamples, 10_000)
    XCTAssertEqual(configuration.maximumTimestampSkew, 3_600)
    XCTAssertEqual(configuration.maximumPlausibleBatteryPowerWatts, 10_000)
    XCTAssertEqual(configuration.maximumPlausibleAdapterPowerWatts, 100_000)
  }

  private func sample(at timestamp: Date, batteryPower: Double?) -> PowerSample {
    PowerSample(
      timestamp: timestamp,
      externalPower: true,
      batteryPowerWatts: batteryPower,
      adapterRatedPowerWatts: 67,
      adapterMeasuredPowerWatts: nil,
      batteryPercent: 50)
  }
}