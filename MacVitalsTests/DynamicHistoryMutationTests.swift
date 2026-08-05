import Dispatch
import Foundation
import XCTest

@testable import MacVitals

final class DynamicHistoryMutationTests: XCTestCase {
  func testInPlaceDictionaryMutationPreservesHistoryAndOutperformsValueCopy() {
    let seriesCount = 24
    let capacity = 512
    let iterations = 2_000

    var legacy: [Int: RingBuffer<Int>] = [:]
    var inPlace: [Int: RingBuffer<Int>] = [:]
    for key in 0..<seriesCount {
      legacy[key] = RingBuffer(capacity: capacity)
      inPlace[key] = RingBuffer(capacity: capacity)
    }

    let legacyStart = DispatchTime.now().uptimeNanoseconds
    for value in 0..<iterations {
      for key in 0..<seriesCount {
        var buffer = legacy[key] ?? RingBuffer(capacity: capacity)
        buffer.append(value)
        legacy[key] = buffer
      }
    }
    let legacyNanoseconds = DispatchTime.now().uptimeNanoseconds - legacyStart

    let inPlaceStart = DispatchTime.now().uptimeNanoseconds
    for value in 0..<iterations {
      for key in 0..<seriesCount {
        inPlace[key, default: RingBuffer(capacity: capacity)].append(value)
      }
    }
    let inPlaceNanoseconds = DispatchTime.now().uptimeNanoseconds - inPlaceStart

    XCTAssertEqual(legacy.keys.sorted(), inPlace.keys.sorted())
    for key in 0..<seriesCount {
      XCTAssertEqual(legacy[key]?.values, inPlace[key]?.values)
    }
    XCTAssertLessThan(inPlaceNanoseconds, legacyNanoseconds)

    let speedup = Double(legacyNanoseconds) / Double(max(inPlaceNanoseconds, 1))
    print(
      "DYNAMIC_HISTORY_MUTATION_BENCHMARK series=\(seriesCount) capacity=\(capacity) "
        + "iterations=\(iterations) legacy_ns=\(legacyNanoseconds) "
        + "in_place_ns=\(inPlaceNanoseconds) "
        + String(format: "speedup=%.2fx", speedup))
  }
}
