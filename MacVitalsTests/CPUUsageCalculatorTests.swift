import XCTest
@testable import MacVitals

final class CPUUsageCalculatorTests: XCTestCase {
  func testDeltaCalculation() throws {
    let result = try CPUUsageCalculator.calculate(
      previous: .init(user: 100, system: 50, idle: 850, nice: 0),
      current: .init(user: 200, system: 100, idle: 1_700, nice: 0))

    XCTAssertEqual(result.total, 15, accuracy: 0.001)
    XCTAssertEqual(result.user, 10, accuracy: 0.001)
    XCTAssertEqual(result.system, 5, accuracy: 0.001)
    XCTAssertEqual(result.idle, 85, accuracy: 0.001)
  }

  func testHandlesDeltasWhoseIntegerSumWouldOverflow() throws {
    let result = try CPUUsageCalculator.calculate(
      previous: .init(user: 0, system: 0, idle: 0, nice: 0),
      current: .init(
        user: UInt64.max,
        system: UInt64.max,
        idle: UInt64.max,
        nice: UInt64.max))

    XCTAssertEqual(result.total, 75, accuracy: 0.001)
    XCTAssertEqual(result.user, 50, accuracy: 0.001)
    XCTAssertEqual(result.system, 25, accuracy: 0.001)
    XCTAssertEqual(result.idle, 25, accuracy: 0.001)
    XCTAssertTrue(result.total.isFinite)
  }

  func testNiceTicksAreIncludedInUserPercentageWithoutOverflow() throws {
    let result = try CPUUsageCalculator.calculate(
      previous: .init(user: 0, system: 0, idle: 0, nice: 0),
      current: .init(
        user: UInt64.max,
        system: 0,
        idle: UInt64.max,
        nice: UInt64.max))

    XCTAssertEqual(result.user, 66.666, accuracy: 0.01)
    XCTAssertEqual(result.idle, 33.333, accuracy: 0.01)
    XCTAssertEqual(result.total, 66.666, accuracy: 0.01)
  }

  func testRejectsCounterReset() {
    XCTAssertThrowsError(
      try CPUUsageCalculator.calculate(
        previous: .init(user: 10, system: 10, idle: 10, nice: 10),
        current: .init(user: 1, system: 1, idle: 1, nice: 1)))
  }

  func testRejectsZeroDelta() {
    let ticks = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
    XCTAssertThrowsError(
      try CPUUsageCalculator.calculate(previous: ticks, current: ticks))
  }
}