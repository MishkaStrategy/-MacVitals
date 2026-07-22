import XCTest
@testable import MacVitals

final class MemoryMathTests: XCTestCase {
    func testPercentIsClamped() {
        XCTAssertEqual(MemoryMath.percent(used: 150, physical: 100), 100)
        XCTAssertEqual(MemoryMath.percent(used: 50, physical: 100), 50)
        XCTAssertEqual(MemoryMath.percent(used: 50, physical: 0), 0)
    }
}
