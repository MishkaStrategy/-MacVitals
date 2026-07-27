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

  func testUsesFiveSecondCadenceForEveryInput() {
    for value in [-10.0, 0.5, 1, 2, 5, 10, 100] {
      XCTAssertEqual(SamplingIntervalPolicy.normalized(value), 5)
    }
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
  }
}
