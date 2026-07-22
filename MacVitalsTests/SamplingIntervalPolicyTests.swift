import XCTest
@testable import MacVitals

final class SamplingIntervalPolicyTests: XCTestCase {
  func testNormalizesNonFiniteAndNonPositiveValuesToDefault() {
    XCTAssertEqual(SamplingIntervalPolicy.normalized(.nan), 2)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(.infinity), 2)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(-.infinity), 2)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(0), 2)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(-1), 2)
  }

  func testPreservesSupportedValues() {
    for value in SamplingIntervalPolicy.supportedValues {
      XCTAssertEqual(SamplingIntervalPolicy.normalized(value), value)
    }
  }

  func testChoosesNearestSupportedValueAndUsesLowerValueForTie() {
    XCTAssertEqual(SamplingIntervalPolicy.normalized(0.7), 0.5)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(1.5), 1)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(4.2), 5)
    XCTAssertEqual(SamplingIntervalPolicy.normalized(100), 10)
  }

  func testSleepNanosecondsCannotTrapOnCorruptInputs() {
    XCTAssertEqual(
      SamplingIntervalPolicy.sleepNanoseconds(
        intervalSeconds: .infinity,
        elapsedMilliseconds: .infinity),
      0)
    XCTAssertEqual(
      SamplingIntervalPolicy.sleepNanoseconds(
        intervalSeconds: .nan,
        elapsedMilliseconds: .nan),
      0)
    XCTAssertEqual(
      SamplingIntervalPolicy.sleepNanoseconds(
        intervalSeconds: 2,
        elapsedMilliseconds: 1_000),
      1_000_000_000)
  }
}