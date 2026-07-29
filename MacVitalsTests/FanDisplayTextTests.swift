import XCTest

@testable import MacVitals

final class FanDisplayTextTests: XCTestCase {
  func testSingleAndDualFanSummaries() {
    let first = MetricNumberFormatter.rpm(1_900) ?? "—"
    let second = MetricNumberFormatter.rpm(2_100) ?? "—"
    XCTAssertEqual(
      FanDisplayText.summary(metric([fan(index: 0, current: 2_100)])),
      second)
    XCTAssertEqual(
      FanDisplayText.summary(
        metric([
          fan(index: 0, current: 1_900),
          fan(index: 1, current: 2_100),
        ])),
      "\(first) / \(second)")
  }

  func testUnavailableAndEmptyFanSummariesRemainExplicit() {
    XCTAssertEqual(
      FanDisplayText.summary(.unavailable(unit: .rpm, availability: .providerError)),
      MetricAvailability.providerError.displayName)
    XCTAssertEqual(FanDisplayText.summary(metric([])), L10n.string("No fan"))
  }

  func testInvalidCurrentValuesNeverAppearAsNaNOrInfinity() {
    for value in [Double.nan, .infinity, -.infinity, -1, 20_001] {
      let summary = FanDisplayText.summary(metric([fan(index: 0, current: value)]))
      let menu = FanDisplayText.menuBar(metric([fan(index: 0, current: value)]))
      XCTAssertEqual(summary, "—")
      XCTAssertEqual(menu, "🌀 —")
      XCTAssertFalse(summary.lowercased().contains("nan"))
      XCTAssertFalse(summary.lowercased().contains("inf"))
    }
  }

  func testDetailIncludesCurrentTargetAndMode() {
    XCTAssertEqual(
      FanDisplayText.detail(
        FanReading(
          index: 0,
          currentRPM: 2_100,
          targetRPM: 2_400,
          minimumRPM: 1_200,
          maximumRPM: 6_000,
          mode: .manual)),
      L10n.format(
        "%@ current · %@ target · %@",
        MetricNumberFormatter.rpm(2_100) ?? "—",
        MetricNumberFormatter.rpm(2_400) ?? "—",
        FanMode.manual.displayName))
  }

  func testRPMFormatterAcceptsOnlyPlausibleFiniteRange() {
    XCTAssertEqual(MetricNumberFormatter.rpm(0), L10n.format("%d RPM", 0))
    XCTAssertEqual(MetricNumberFormatter.rpm(20_000), L10n.format("%d RPM", 20_000))
    for value in [Double.nan, .infinity, -.infinity, -0.01, 20_000.01] {
      XCTAssertNil(MetricNumberFormatter.rpm(value))
      XCTAssertNil(MetricNumberFormatter.rpmNumber(value))
    }
  }

  private func metric(_ fans: [FanReading]) -> MetricValue<FanStats> {
    MetricValue(
      value: FanStats(fans: fans),
      unit: .rpm,
      availability: .available,
      quality: .experimental,
      source: .appleSMC,
      timestamp: Date(timeIntervalSince1970: 100),
      isEstimated: false,
      message: nil)
  }

  private func fan(index: Int, current: Double?) -> FanReading {
    FanReading(
      index: index,
      currentRPM: current,
      targetRPM: 2_400,
      minimumRPM: 1_200,
      maximumRPM: 6_000,
      mode: .automatic)
  }
}
