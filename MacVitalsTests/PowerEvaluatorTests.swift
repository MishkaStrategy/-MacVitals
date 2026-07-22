import XCTest

@testable import MacVitals

final class PowerEvaluatorTests: XCTestCase {
  func testSustainedBatteryDischargeIsInsufficient() {
    var evaluator = ChargerSufficiencyEvaluator(
      configuration: .init(
        insufficientDischargeWatts: 2,
        borderlineDischargeWatts: 0.5,
        confirmationDuration: 20,
        minimumSamples: 5
      )
    )
    let start = Date()
    var result: PowerAssessment?
    for index in 0..<6 {
      result = evaluator.evaluate(
        sample(
          at: start.addingTimeInterval(Double(index) * 4),
          batteryPower: -4,
          adapterRatedPower: 30
        )
      )
    }
    XCTAssertEqual(result?.status, .insufficient)
    XCTAssertEqual(result?.batteryPowerWatts, -4)
  }

  func testChargingBatteryIsNotInsufficient() {
    var evaluator = ChargerSufficiencyEvaluator(
      configuration: .init(
        confirmationDuration: 15,
        minimumSamples: 3
      )
    )
    let start = Date()
    var result: PowerAssessment?
    for index in 0..<4 {
      result = evaluator.evaluate(
        sample(
          at: start.addingTimeInterval(Double(index) * 5),
          batteryPower: 5,
          adapterRatedPower: 67
        )
      )
    }
    XCTAssertEqual(result?.status, .chargingBattery)
  }

  func testRequiresMinimumConfirmationDuration() {
    var evaluator = ChargerSufficiencyEvaluator(
      configuration: .init(
        confirmationDuration: 20,
        minimumSamples: 3
      )
    )
    let start = Date()
    var result: PowerAssessment?
    for index in 0..<5 {
      result = evaluator.evaluate(
        sample(
          at: start.addingTimeInterval(Double(index)),
          batteryPower: -10,
          adapterRatedPower: 30
        )
      )
    }
    XCTAssertEqual(result?.status, .unknown)
  }

  func testReconnectResetsConfirmationWindow() {
    var evaluator = ChargerSufficiencyEvaluator(
      configuration: .init(
        confirmationDuration: 4,
        minimumSamples: 2
      )
    )
    let start = Date()
    _ = evaluator.evaluate(sample(at: start, batteryPower: -4, adapterRatedPower: 30))
    let first = evaluator.evaluate(
      sample(at: start.addingTimeInterval(4), batteryPower: -4, adapterRatedPower: 30)
    )
    XCTAssertEqual(first.status, .insufficient)

    _ = evaluator.evaluate(
      sample(
        at: start.addingTimeInterval(5),
        externalPower: false,
        batteryPower: -4,
        adapterRatedPower: nil
      )
    )
    let afterReconnect = evaluator.evaluate(
      sample(at: start.addingTimeInterval(6), batteryPower: -4, adapterRatedPower: 30)
    )
    XCTAssertEqual(afterReconnect.status, .unknown)
  }

  func testHysteresisPreventsImmediateInsufficientFlap() {
    var evaluator = ChargerSufficiencyEvaluator(
      configuration: .init(
        insufficientDischargeWatts: 2,
        borderlineDischargeWatts: 0.5,
        hysteresisWatts: 0.4,
        confirmationDuration: 4,
        minimumSamples: 2
      )
    )
    let start = Date()
    _ = evaluator.evaluate(sample(at: start, batteryPower: -3, adapterRatedPower: 30))
    XCTAssertEqual(
      evaluator.evaluate(
        sample(at: start.addingTimeInterval(4), batteryPower: -3, adapterRatedPower: 30)
      ).status,
      .insufficient
    )

    _ = evaluator.evaluate(
      sample(at: start.addingTimeInterval(8), batteryPower: -1.8, adapterRatedPower: 30)
    )
    XCTAssertEqual(
      evaluator.evaluate(
        sample(at: start.addingTimeInterval(12), batteryPower: -1.8, adapterRatedPower: 30)
      ).status,
      .insufficient
    )
  }

  func testFullBatteryNearZeroUsesAdapterOnlyStatus() {
    var evaluator = ChargerSufficiencyEvaluator(
      configuration: .init(confirmationDuration: 4, minimumSamples: 2)
    )
    let start = Date()
    _ = evaluator.evaluate(
      sample(at: start, batteryPower: 0.1, adapterRatedPower: 67, batteryPercent: 100)
    )
    let result = evaluator.evaluate(
      sample(
        at: start.addingTimeInterval(4),
        batteryPower: 0.1,
        adapterRatedPower: 67,
        batteryPercent: 100
      )
    )
    XCTAssertEqual(result.status, .powerAdapterOnly)
  }

  func testMismatchedTimestampsSuppressSystemPowerEstimate() {
    var evaluator = ChargerSufficiencyEvaluator(
      configuration: .init(
        confirmationDuration: 4,
        minimumSamples: 2,
        maximumTimestampSkew: 1
      )
    )
    let start = Date()
    _ = evaluator.evaluate(
      sample(
        at: start,
        batteryPower: 2,
        adapterRatedPower: 67,
        adapterMeasuredPower: 30,
        batteryTimestamp: start,
        adapterTimestamp: start.addingTimeInterval(5)
      )
    )
    let result = evaluator.evaluate(
      sample(
        at: start.addingTimeInterval(4),
        batteryPower: 2,
        adapterRatedPower: 67,
        adapterMeasuredPower: 30,
        batteryTimestamp: start.addingTimeInterval(4),
        adapterTimestamp: start.addingTimeInterval(9)
      )
    )
    XCTAssertNil(result.estimatedSystemPowerWatts)
  }

  func testAlignedMeasuredPowerProducesDerivedSystemPower() {
    var evaluator = ChargerSufficiencyEvaluator(
      configuration: .init(confirmationDuration: 4, minimumSamples: 2)
    )
    let start = Date()
    _ = evaluator.evaluate(
      sample(
        at: start,
        batteryPower: 5,
        adapterRatedPower: 67,
        adapterMeasuredPower: 30
      )
    )
    let result = evaluator.evaluate(
      sample(
        at: start.addingTimeInterval(4),
        batteryPower: 5,
        adapterRatedPower: 67,
        adapterMeasuredPower: 30
      )
    )
    XCTAssertEqual(result.estimatedSystemPowerWatts ?? -1, 25, accuracy: 0.001)
    XCTAssertNil(result.powerBalanceWatts)
  }

  func testNoAdapterIsNotConnected() {
    var evaluator = ChargerSufficiencyEvaluator()
    let result = evaluator.evaluate(
      sample(
        at: Date(),
        externalPower: false,
        batteryPower: -10,
        adapterRatedPower: nil
      )
    )
    XCTAssertEqual(result.status, .notConnected)
  }

  private func sample(
    at timestamp: Date,
    externalPower: Bool = true,
    batteryPower: Double?,
    adapterRatedPower: Double?,
    adapterMeasuredPower: Double? = nil,
    batteryPercent: Double = 50,
    batteryTimestamp: Date? = nil,
    adapterTimestamp: Date? = nil
  ) -> PowerSample {
    PowerSample(
      timestamp: timestamp,
      externalPower: externalPower,
      batteryPowerWatts: batteryPower,
      adapterRatedPowerWatts: adapterRatedPower,
      adapterMeasuredPowerWatts: adapterMeasuredPower,
      batteryPercent: batteryPercent,
      batteryTimestamp: batteryTimestamp,
      adapterTimestamp: adapterTimestamp
    )
  }
}
