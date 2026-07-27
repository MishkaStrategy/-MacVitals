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
}
