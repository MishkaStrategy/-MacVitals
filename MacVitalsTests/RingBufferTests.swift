import Dispatch
import XCTest

@testable import MacVitals

final class RingBufferTests: XCTestCase {
  func testCapacityIsBounded() {
    var buffer = RingBuffer<Int>(capacity: 3)
    for value in 1...5 { buffer.append(value) }
    XCTAssertEqual(buffer.values, [3, 4, 5])
  }

  func testMultipleWraparoundsPreserveChronologicalOrder() {
    var buffer = RingBuffer<Int>(capacity: 4)
    for value in 1...12 { buffer.append(value) }

    XCTAssertEqual(buffer.values, [9, 10, 11, 12])
    XCTAssertEqual(buffer.capacity, 4)
  }

  func testCapacityIsNormalizedAndSingleSlotWraps() {
    var buffer = RingBuffer<Int>(capacity: 0)
    XCTAssertEqual(buffer.capacity, 1)

    buffer.append(1)
    buffer.append(2)
    buffer.append(3)

    XCTAssertEqual(buffer.values, [3])
  }

  func testRemoveAllResetsOrderingAndAllowsReuse() {
    var buffer = RingBuffer<Int>(capacity: 3)
    for value in 1...5 { buffer.append(value) }
    XCTAssertEqual(buffer.values, [3, 4, 5])

    buffer.removeAll()
    XCTAssertEqual(buffer.values, [])

    buffer.append(10)
    buffer.append(11)
    XCTAssertEqual(buffer.values, [10, 11])
  }

  func testReadingValuesDoesNotChangeSubsequentWraparound() {
    var buffer = RingBuffer<Int>(capacity: 3)
    for value in 1...4 { buffer.append(value) }

    XCTAssertEqual(buffer.values, [2, 3, 4])
    XCTAssertEqual(buffer.values, [2, 3, 4])

    buffer.append(5)
    XCTAssertEqual(buffer.values, [3, 4, 5])
  }

  func testSteadyStateAppendOutperformsLegacyFrontShift() {
    let capacity = 3_600
    let iterations = 20_000

    var legacy = LegacyShiftBuffer<Int>(capacity: capacity)
    for value in 0..<capacity { legacy.append(value) }
    let legacyStart = DispatchTime.now().uptimeNanoseconds
    for value in capacity..<(capacity + iterations) { legacy.append(value) }
    let legacyNanoseconds = DispatchTime.now().uptimeNanoseconds - legacyStart

    var circular = RingBuffer<Int>(capacity: capacity)
    for value in 0..<capacity { circular.append(value) }
    let circularStart = DispatchTime.now().uptimeNanoseconds
    for value in capacity..<(capacity + iterations) { circular.append(value) }
    let circularNanoseconds = DispatchTime.now().uptimeNanoseconds - circularStart

    let expected = Array(iterations..<(iterations + capacity))
    XCTAssertEqual(legacy.values, expected)
    XCTAssertEqual(circular.values, expected)
    XCTAssertLessThan(circularNanoseconds, legacyNanoseconds)

    let speedup = Double(legacyNanoseconds) / Double(max(circularNanoseconds, 1))
    print(
      "RING_BUFFER_BENCHMARK capacity=\(capacity) iterations=\(iterations) "
        + "legacy_ns=\(legacyNanoseconds) circular_ns=\(circularNanoseconds) "
        + String(format: "speedup=%.2fx", speedup))
  }

  func testHistoryWithoutDiscontinuityUsesOneSegment() {
    let start = Date(timeIntervalSince1970: 100)
    let points = HistoryChartSegmentation.points(
      from: [
        TimedPoint(timestamp: start, value: 10),
        TimedPoint(timestamp: start.addingTimeInterval(1), value: 20),
      ])

    XCTAssertEqual(points.map(\.value), [10, 20])
    XCTAssertEqual(points.map(\.segment), [0, 0])
  }

  func testSleepMarkerStartsANewChartSegment() {
    let start = Date(timeIntervalSince1970: 100)
    let points = HistoryChartSegmentation.points(
      from: [
        TimedPoint(timestamp: start, value: 10),
        TimedPoint(timestamp: start.addingTimeInterval(1), value: 20),
        TimedPoint(
          timestamp: start.addingTimeInterval(2),
          value: nil,
          discontinuity: true),
        TimedPoint(timestamp: start.addingTimeInterval(3), value: 30),
        TimedPoint(timestamp: start.addingTimeInterval(4), value: 40),
      ])

    XCTAssertEqual(points.map(\.value), [10, 20, 30, 40])
    XCTAssertEqual(points.map(\.segment), [0, 0, 1, 1])
  }

  func testLeadingConsecutiveAndTrailingMarkersDoNotCreateEmptySegments() {
    let start = Date(timeIntervalSince1970: 100)
    let points = HistoryChartSegmentation.points(
      from: [
        TimedPoint(timestamp: start, value: nil, discontinuity: true),
        TimedPoint(timestamp: start.addingTimeInterval(1), value: 10),
        TimedPoint(timestamp: start.addingTimeInterval(2), value: nil, discontinuity: true),
        TimedPoint(timestamp: start.addingTimeInterval(3), value: nil, discontinuity: true),
        TimedPoint(timestamp: start.addingTimeInterval(4), value: 20),
        TimedPoint(timestamp: start.addingTimeInterval(5), value: nil, discontinuity: true),
      ])

    XCTAssertEqual(points.map(\.value), [10, 20])
    XCTAssertEqual(points.map(\.segment), [0, 1])
  }

  func testUnavailableAndNonFinitePointsAreOmittedWithoutInventingABreak() {
    let start = Date(timeIntervalSince1970: 100)
    let points = HistoryChartSegmentation.points(
      from: [
        TimedPoint(timestamp: start, value: 10),
        TimedPoint(timestamp: start.addingTimeInterval(1), value: nil),
        TimedPoint(timestamp: start.addingTimeInterval(2), value: .nan),
        TimedPoint(timestamp: start.addingTimeInterval(3), value: .infinity),
        TimedPoint(timestamp: start.addingTimeInterval(4), value: 20),
      ])

    XCTAssertEqual(points.map(\.value), [10, 20])
    XCTAssertEqual(points.map(\.segment), [0, 0])
  }

  func testSegmentationPreservesPointIdentityAndTimestamp() throws {
    let source = TimedPoint(timestamp: Date(timeIntervalSince1970: 123), value: 42)
    let chartPoint = try XCTUnwrap(HistoryChartSegmentation.points(from: [source]).first)

    XCTAssertEqual(chartPoint.id, source.id)
    XCTAssertEqual(chartPoint.timestamp, source.timestamp)
    XCTAssertEqual(chartPoint.value, 42)
  }

  func testSnapshotHistoryPointsUseSnapshotTimestampForBothSeries() {
    let snapshot = SystemSnapshot.empty
    let points = SnapshotHistoryPoints.make(from: snapshot)

    XCTAssertEqual(points.cpu.timestamp, snapshot.timestamp)
    XCTAssertEqual(points.memory.timestamp, snapshot.timestamp)
    XCTAssertNil(points.cpu.value)
    XCTAssertNil(points.memory.value)
  }
}

private struct LegacyShiftBuffer<Element> {
  private var storage: [Element] = []
  private let capacity: Int

  init(capacity: Int) {
    self.capacity = max(1, capacity)
    storage.reserveCapacity(self.capacity)
  }

  var values: [Element] { storage }

  mutating func append(_ element: Element) {
    if storage.count == capacity { storage.removeFirst() }
    storage.append(element)
  }
}
