import XCTest
@testable import MacVitals

final class ProcessSamplingClockToleranceTests: XCTestCase {
  func testToleranceIsTenPercentOfShortCadenceAndCappedAtOneHundredMilliseconds() {
    XCTAssertEqual(
      ProcessSamplingClockPolicy.toleranceSeconds(for: 0.25),
      0.025,
      accuracy: 0.000_001)
    XCTAssertEqual(
      ProcessSamplingClockPolicy.toleranceSeconds(for: 1),
      0.1,
      accuracy: 0.000_001)
    XCTAssertEqual(
      ProcessSamplingClockPolicy.toleranceSeconds(for: 5),
      0.1,
      accuracy: 0.000_001)
    XCTAssertEqual(
      ProcessSamplingClockPolicy.toleranceSeconds(for: 30),
      0.1,
      accuracy: 0.000_001)
  }

  func testToleranceFailsClosedForInvalidIntervals() {
    XCTAssertEqual(ProcessSamplingClockPolicy.toleranceSeconds(for: 0), 0)
    XCTAssertEqual(ProcessSamplingClockPolicy.toleranceSeconds(for: -1), 0)
    XCTAssertEqual(ProcessSamplingClockPolicy.toleranceSeconds(for: .infinity), 0)
    XCTAssertEqual(ProcessSamplingClockPolicy.toleranceSeconds(for: .nan), 0)
  }
}
