import XCTest

@testable import MacVitals

final class DynamicHistoryMutationTests: XCTestCase {
  func testInPlaceDictionaryMutationPreservesWrappedHistory() {
    let seriesCount = 24
    let capacity = 512
    let iterations = 2_000
    let expectedValues = Array((iterations - capacity)..<iterations)

    var reference: [Int: RingBuffer<Int>] = [:]
    var inPlace: [Int: RingBuffer<Int>] = [:]
    for key in 0..<seriesCount {
      reference[key] = RingBuffer(capacity: capacity)
      inPlace[key] = RingBuffer(capacity: capacity)
    }

    for value in 0..<iterations {
      for key in 0..<seriesCount {
        var buffer = reference[key] ?? RingBuffer(capacity: capacity)
        buffer.append(value)
        reference[key] = buffer

        inPlace[key, default: RingBuffer(capacity: capacity)].append(value)
      }
    }

    XCTAssertEqual(reference.keys.sorted(), Array(0..<seriesCount))
    XCTAssertEqual(inPlace.keys.sorted(), Array(0..<seriesCount))
    for key in 0..<seriesCount {
      XCTAssertEqual(reference[key]?.values, expectedValues)
      XCTAssertEqual(inPlace[key]?.values, expectedValues)
      XCTAssertEqual(reference[key]?.values, inPlace[key]?.values)
    }
  }

  func testDefaultSubscriptInsertsOnlyRequestedSeries() {
    var buffers: [Int: RingBuffer<Int>] = [:]

    buffers[7, default: RingBuffer(capacity: 3)].append(10)
    buffers[7, default: RingBuffer(capacity: 3)].append(20)

    XCTAssertEqual(buffers.keys.sorted(), [7])
    XCTAssertEqual(buffers[7]?.values, [10, 20])
  }
}
