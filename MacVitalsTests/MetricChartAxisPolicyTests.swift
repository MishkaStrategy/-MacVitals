import Foundation
import Testing
@testable import MacVitals

struct MetricChartAxisPolicyTests {
  @Test
  func shortRangeUsesFiveSecondMinorCadence() {
    #expect(MetricChartAxisPolicy.minorSecondStride(for: 5 * 60) == 5)
  }

  @Test
  func longerRangesDoNotRenderDenseMinorCadence() {
    #expect(MetricChartAxisPolicy.minorSecondStride(for: 15 * 60) == nil)
    #expect(MetricChartAxisPolicy.minorSecondStride(for: 60 * 60) == nil)
  }

  @Test
  func invalidRangesDoNotRenderMinorCadence() {
    #expect(MetricChartAxisPolicy.minorSecondStride(for: 0) == nil)
    #expect(MetricChartAxisPolicy.minorSecondStride(for: -.infinity) == nil)
    #expect(MetricChartAxisPolicy.minorSecondStride(for: .nan) == nil)
  }
}
