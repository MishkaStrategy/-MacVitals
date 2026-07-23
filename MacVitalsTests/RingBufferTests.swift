import XCTest

@testable import MacVitals

final class RingBufferTests: XCTestCase {
  func testCapacityIsBounded() {
    var buffer = RingBuffer<Int>(capacity: 3)
    for value in 1...5 { buffer.append(value) }
    XCTAssertEqual(buffer.values, [3, 4, 5])
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
}
