import XCTest

@testable import MacVitals

final class SamplingDiagnosticsTests: XCTestCase {
  func testTimingsClampNegativeAndNonFiniteValues() {
    let timings = SamplingTimings(
      cpuMilliseconds: -1,
      memoryMilliseconds: .infinity,
      batteryMilliseconds: .nan,
      adapterMilliseconds: 4,
      gpuMilliseconds: 5,
      powerModelMilliseconds: 6,
      totalMilliseconds: -20)

    XCTAssertEqual(timings.cpuMilliseconds, 0)
    XCTAssertEqual(timings.memoryMilliseconds, 0)
    XCTAssertEqual(timings.batteryMilliseconds, 0)
    XCTAssertEqual(timings.adapterMilliseconds, 4)
    XCTAssertEqual(timings.totalMilliseconds, 0)
  }

  func testSamplingHealthDetectsIntervalOverrun() {
    let timings = SamplingTimings(
      cpuMilliseconds: 100,
      memoryMilliseconds: 100,
      batteryMilliseconds: 100,
      adapterMilliseconds: 100,
      gpuMilliseconds: 100,
      powerModelMilliseconds: 100,
      totalMilliseconds: 600)

    XCTAssertTrue(
      SamplingHealth(timings: timings, configuredIntervalSeconds: 0.5).overranInterval)
    XCTAssertFalse(
      SamplingHealth(timings: timings, configuredIntervalSeconds: 2).overranInterval)
  }

  func testRemainingDelayAccountsForSamplingDuration() {
    XCTAssertEqual(
      SamplingTimingMath.remainingDelaySeconds(
        intervalSeconds: 2,
        elapsedMilliseconds: 500),
      1.5,
      accuracy: 0.000_001)
    XCTAssertEqual(
      SamplingTimingMath.remainingDelaySeconds(
        intervalSeconds: 0.5,
        elapsedMilliseconds: 800),
      0.05,
      accuracy: 0.000_001)
  }

  func testRemainingDelaySanitizesInvalidMinimumDelay() {
    for minimum in [Double.nan, .infinity, -.infinity, -1, 0] {
      XCTAssertEqual(
        SamplingTimingMath.remainingDelaySeconds(
          intervalSeconds: 0.5,
          elapsedMilliseconds: 800,
          minimumDelaySeconds: minimum),
        0.05,
        accuracy: 0.000_001)
    }
  }

  func testNanosecondConversionHandlesClockRegression() {
    XCTAssertEqual(
      SamplingTimingMath.milliseconds(startNanoseconds: 2_000_000, endNanoseconds: 3_500_000),
      1.5,
      accuracy: 0.000_001)
    XCTAssertEqual(
      SamplingTimingMath.milliseconds(startNanoseconds: 5, endNanoseconds: 4),
      0)
  }
}
