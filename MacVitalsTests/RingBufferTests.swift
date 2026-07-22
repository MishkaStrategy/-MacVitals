import XCTest
@testable import MacVitals

final class RingBufferTests: XCTestCase {
    func testCapacityIsBounded() {
        var buffer = RingBuffer<Int>(capacity: 3)
        (1...5).forEach { buffer.append($0) }
        XCTAssertEqual(buffer.values, [3, 4, 5])
    }
}
