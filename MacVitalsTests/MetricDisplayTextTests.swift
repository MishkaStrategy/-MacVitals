import XCTest

@testable import MacVitals

final class MetricDisplayTextTests: XCTestCase {
  func testMetricNumberFormatterRejectsInvalidValuesWithoutTrapping() {
    for value in [Double.nan, .infinity, -.infinity, -0.01, 100.01] {
      XCTAssertEqual(MetricNumberFormatter.percentage(value), "—")
    }
    XCTAssertNil(MetricNumberFormatter.ratedWatts(.nan))
    XCTAssertNil(MetricNumberFormatter.ratedWatts(-1))
    XCTAssertNil(MetricNumberFormatter.decimalWatts(.infinity))
    XCTAssertNil(MetricNumberFormatter.decimalWatts(-1))
    XCTAssertNil(MetricNumberFormatter.isNegative(.nan))
    XCTAssertEqual(MetricNumberFormatter.isNegative(-2), true)
  }

  func testMetricNumberFormatterFormatsValidBoundaries() {
    XCTAssertEqual(MetricNumberFormatter.percentage(0), "0%")
    XCTAssertEqual(MetricNumberFormatter.percentage(99.6), "100%")
    XCTAssertEqual(MetricNumberFormatter.ratedWatts(67.4), "Rated 67 W")
    XCTAssertEqual(MetricNumberFormatter.decimalWatts(12.34, estimated: true), "~12.3 W")
    XCTAssertEqual(MetricNumberFormatter.decimalWatts(-4.25, absolute: true), "4.2 W")
  }

  func testMetricNumberFormatterFuzzNeverReturnsNonFiniteText() {
    var state: UInt64 = 0xD15EA5E
    func next() -> UInt64 {
      state = state &* 6_364_136_223_846_793_005 &+ 1
      return state
    }

    for index in 0..<50_000 {
      let raw: Double
      switch index % 17 {
      case 0: raw = .nan
      case 1: raw = .infinity
      case 2: raw = -.infinity
      default: raw = Double(Int64(bitPattern: next())) / 1_000_000
      }

      let outputs = [
        MetricNumberFormatter.percentage(raw),
        MetricNumberFormatter.ratedWatts(raw),
        MetricNumberFormatter.decimalWatts(raw),
        MetricNumberFormatter.decimalWatts(raw, estimated: true),
        MetricNumberFormatter.decimalWatts(raw, absolute: true),
      ].compactMap { $0 }
      for output in outputs {
        XCTAssertFalse(output.lowercased().contains("nan"))
        XCTAssertFalse(output.lowercased().contains("inf"))
      }
    }
  }

  func testEveryPowerStatusHasAccurateDisplayMetadata() {
    let statuses: [PowerSufficiencyStatus] = [
      .sufficient,
      .insufficient,
      .borderline,
      .chargingBattery,
      .notConnected,
      .sensorConflict,
      .powerAdapterOnly,
      .unknown,
    ]
    for status in statuses {
      XCTAssertFalse(status.displayName.isEmpty)
      XCTAssertFalse(status.symbolName.isEmpty)
    }
    XCTAssertEqual(PowerSufficiencyStatus.unknown.symbolName, "questionmark.circle")
    XCTAssertEqual(PowerSufficiencyStatus.sensorConflict.symbolName, "exclamationmark.triangle")
    XCTAssertEqual(PowerSufficiencyStatus.powerAdapterOnly.symbolName, "powerplug")
    XCTAssertEqual(PowerSufficiencyStatus.notConnected.symbolName, "battery.75percent")
  }
}
