import XCTest
@testable import MacVitals

final class CPUUsageCalculatorTests: XCTestCase {
    func testDeltaCalculation() throws {
        let result = try CPUUsageCalculator.calculate(previous: .init(user: 100, system: 50, idle: 850, nice: 0),
                                                       current: .init(user: 200, system: 100, idle: 1700, nice: 0))
        XCTAssertEqual(result.total, 15, accuracy: 0.001)
        XCTAssertEqual(result.idle, 85, accuracy: 0.001)
    }
    func testRejectsCounterReset() { XCTAssertThrowsError(try CPUUsageCalculator.calculate(previous: .init(user: 10, system: 10, idle: 10, nice: 10), current: .init(user: 1, system: 1, idle: 1, nice: 1))) }
    func testRejectsZeroDelta() { let t = CPUTicks(user: 1, system: 1, idle: 1, nice: 1); XCTAssertThrowsError(try CPUUsageCalculator.calculate(previous: t, current: t)) }
}
