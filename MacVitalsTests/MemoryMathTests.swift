import XCTest
@testable import MacVitals

final class MemoryMathTests: XCTestCase {
  func testPercentIsClamped() {
    XCTAssertEqual(MemoryMath.percent(used: 150, physical: 100), 100)
    XCTAssertEqual(MemoryMath.percent(used: 50, physical: 100), 50)
    XCTAssertEqual(MemoryMath.percent(used: 50, physical: 0), 0)
  }

  func testUsedBytesIncludesActiveWiredAndCompressedOnly() {
    XCTAssertEqual(MemoryMath.usedBytes(active: 40, wired: 20, compressed: 10), 70)
  }

  func testUsedBytesSaturatesOnOverflow() {
    XCTAssertEqual(
      MemoryMath.usedBytes(active: UInt64.max, wired: 1, compressed: 1),
      UInt64.max)
  }

  func testAvailableBytesDoesNotUnderflow() {
    XCTAssertEqual(MemoryMath.availableBytes(physical: 100, used: 40), 60)
    XCTAssertEqual(MemoryMath.availableBytes(physical: 100, used: 120), 0)
  }

  func testPageConversionSaturatesOnOverflow() {
    XCTAssertEqual(MemoryMath.bytes(pages: 4, pageSize: 4096), 16_384)
    XCTAssertEqual(MemoryMath.bytes(pages: UInt64.max, pageSize: 4096), UInt64.max)
  }
}
