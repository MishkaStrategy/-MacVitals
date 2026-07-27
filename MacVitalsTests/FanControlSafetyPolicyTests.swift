import XCTest

@testable import MacVitals

final class FanControlSafetyPolicyTests: XCTestCase {
  func testNominalBoostAcceptsOnlyCoolingIncrease() throws {
    let fan = makeFan(current: 2_500, minimum: 1_200, maximum: 6_000)
    let range = try XCTUnwrap(FanControlSafetyPolicy.safeBoostRange(for: fan))
    XCTAssertEqual(range.lowerBound, 3_300, accuracy: 0.01)
    XCTAssertEqual(range.upperBound, 6_000, accuracy: 0.01)

    let plan = try FanControlSafetyPolicy.plan(
      fan: fan,
      requestedRPM: 4_000,
      leaseSeconds: 300,
      thermalSeverity: .nominal)
    XCTAssertEqual(plan.targetRPM, 4_000)
    XCTAssertEqual(plan.leaseSeconds, 300)
  }

  func testRequestBelowSafetyFloorIsRejected() {
    XCTAssertThrowsError(
      try FanControlSafetyPolicy.plan(
        fan: makeFan(current: 4_000, minimum: 1_200, maximum: 6_000),
        requestedRPM: 3_900,
        leaseSeconds: 300,
        thermalSeverity: .nominal)
    ) { error in
      guard case FanControlSafetyError.requestBelowSafetyFloor(let floor) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertEqual(floor, 4_000)
    }
  }

  func testFairThermalStateRaisesTargetToEightyPercent() throws {
    let plan = try FanControlSafetyPolicy.plan(
      fan: makeFan(current: 2_000, minimum: 1_200, maximum: 6_000),
      requestedRPM: 3_500,
      leaseSeconds: 300,
      thermalSeverity: .fair)
    XCTAssertEqual(plan.targetRPM, 4_800, accuracy: 0.01)
  }

  func testSeriousAndCriticalThermalStatesForceMaximum() throws {
    for severity in [FanThermalSeverity.serious, .critical] {
      let plan = try FanControlSafetyPolicy.plan(
        fan: makeFan(current: 2_000, minimum: 1_200, maximum: 6_000),
        requestedRPM: 3_500,
        leaseSeconds: 300,
        thermalSeverity: severity)
      XCTAssertEqual(plan.targetRPM, 6_000)
    }
  }

  func testLeaseIsClampedToSafeWindow() throws {
    let fan = makeFan(current: 2_000, minimum: 1_200, maximum: 6_000)
    XCTAssertEqual(
      try FanControlSafetyPolicy.plan(
        fan: fan, requestedRPM: 4_000, leaseSeconds: 1, thermalSeverity: .nominal
      ).leaseSeconds,
      30)
    XCTAssertEqual(
      try FanControlSafetyPolicy.plan(
        fan: fan, requestedRPM: 4_000, leaseSeconds: 10_000, thermalSeverity: .nominal
      ).leaseSeconds,
      900)
  }

  func testInvalidRangeIndexAndNumbersFailClosed() {
    let invalidFans = [
      makeFan(index: -1, current: 2_000, minimum: 1_200, maximum: 6_000),
      makeFan(index: 8, current: 2_000, minimum: 1_200, maximum: 6_000),
      makeFan(current: 2_000, minimum: 6_000, maximum: 1_200),
      makeFan(current: 2_000, minimum: 0, maximum: 6_000),
      makeFan(current: 2_000, minimum: 1_200, maximum: .nan),
    ]
    for fan in invalidFans {
      XCTAssertNil(FanControlSafetyPolicy.safeBoostRange(for: fan))
      XCTAssertThrowsError(
        try FanControlSafetyPolicy.plan(
          fan: fan, requestedRPM: 4_000, leaseSeconds: 300, thermalSeverity: .nominal))
    }
  }

  func testNonFiniteRequestsAndLeasesFailClosed() {
    let fan = makeFan(current: 2_000, minimum: 1_200, maximum: 6_000)
    for requested in [Double.nan, .infinity, -.infinity, -1] {
      XCTAssertThrowsError(
        try FanControlSafetyPolicy.plan(
          fan: fan, requestedRPM: requested, leaseSeconds: 300, thermalSeverity: .nominal))
    }
    for lease in [Double.nan, .infinity, -.infinity, 0, -1] {
      XCTAssertThrowsError(
        try FanControlSafetyPolicy.plan(
          fan: fan, requestedRPM: 4_000, leaseSeconds: lease, thermalSeverity: .nominal))
    }
  }

  func testFuzzNeverProducesTargetOutsideHardwareRange() throws {
    let fan = makeFan(current: 2_100, minimum: 1_200, maximum: 6_000)
    let range = try XCTUnwrap(FanControlSafetyPolicy.safeBoostRange(for: fan))
    var state: UInt64 = 0xFACA_DE01
    for index in 0..<20_000 {
      state = state &* 6_364_136_223_846_793_005 &+ 1
      let fraction = Double(state % 10_001) / 10_000
      let requested = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
      let severity: FanThermalSeverity = [.nominal, .fair, .serious, .critical][index % 4]
      let plan = try FanControlSafetyPolicy.plan(
        fan: fan,
        requestedRPM: requested,
        leaseSeconds: Double((state % 2_000) + 1),
        thermalSeverity: severity)
      XCTAssertTrue(range.contains(plan.targetRPM))
      XCTAssertTrue((30...900).contains(plan.leaseSeconds))
    }
  }

  private func makeFan(
    index: Int = 0,
    current: Double?,
    minimum: Double?,
    maximum: Double?
  ) -> FanReading {
    FanReading(
      index: index,
      currentRPM: current,
      targetRPM: current,
      minimumRPM: minimum,
      maximumRPM: maximum,
      mode: .automatic)
  }
}
