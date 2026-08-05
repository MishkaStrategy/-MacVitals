import Foundation
import XCTest

@testable import MacVitals

final class MetricHistoryChartModelTests: XCTestCase {
  func testPowerModelPreservesSourceIdentityAndDiscontinuitySegments() {
    let start = Date(timeIntervalSince1970: 1_000)
    let first = TimedPoint(timestamp: start, value: 12)
    let discontinuity = TimedPoint(
      timestamp: start.addingTimeInterval(1),
      value: nil,
      discontinuity: true)
    let second = TimedPoint(timestamp: start.addingTimeInterval(2), value: -8)

    let model = MetricHistoryChartModelBuilder.power(
      series: [PowerHistorySeries(name: "Battery", history: [first, discontinuity, second])],
      cutoff: .distantPast)

    XCTAssertEqual(model.points.map(\.id), [first.id, second.id])
    XCTAssertEqual(model.points.map(\.segment), [0, 1])
    XCTAssertEqual(model.points.map(\.series), ["Battery", "Battery"])
    XCTAssertTrue(model.yDomain.contains(0))
    XCTAssertTrue(model.yDomain.contains(-8))
    XCTAssertTrue(model.yDomain.contains(12))
  }

  func testFanModelSortsSeriesAndComputesDomainInOneModel() {
    let start = Date(timeIntervalSince1970: 2_000)
    let fanZero = TimedPoint(timestamp: start, value: 1_800)
    let fanOne = TimedPoint(timestamp: start, value: 3_200)

    let model = MetricHistoryChartModelBuilder.fans(
      histories: [1: [fanOne], 0: [fanZero]],
      cutoff: .distantPast)

    XCTAssertEqual(model.points.map(\.fanIndex), [0, 1])
    XCTAssertEqual(model.points.map(\.id), [fanZero.id, fanOne.id])
    XCTAssertEqual(model.yDomain, 1_000...4_000)
  }

  func testTemperatureModelFiltersCutoffAndIgnoresNonFiniteValues() {
    let start = Date(timeIntervalSince1970: 3_000)
    let expired = TimedPoint(timestamp: start, value: 20)
    let valid = TimedPoint(timestamp: start.addingTimeInterval(10), value: 63)
    let invalid = TimedPoint(timestamp: start.addingTimeInterval(11), value: .infinity)

    let model = MetricHistoryChartModelBuilder.temperature(
      history: [expired, valid, invalid],
      cutoff: start.addingTimeInterval(5))

    XCTAssertEqual(model.points.map(\.id), [valid.id])
    XCTAssertEqual(model.points.map(\.value), [63])
    XCTAssertEqual(model.yDomain, 50...80)
  }

  func testDiscontinuityBeforeFirstVisibleValueDoesNotCreateEmptySegment() {
    let start = Date(timeIntervalSince1970: 4_000)
    let discontinuity = TimedPoint(timestamp: start, value: nil, discontinuity: true)
    let value = TimedPoint(timestamp: start.addingTimeInterval(1), value: 42)

    let model = MetricHistoryChartModelBuilder.temperature(
      history: [discontinuity, value],
      cutoff: .distantPast)

    XCTAssertEqual(model.points.map(\.segment), [0])
  }
}
