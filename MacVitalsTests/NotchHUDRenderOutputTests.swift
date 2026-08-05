import XCTest

@testable import MacVitals

final class NotchHUDRenderOutputTests: XCTestCase {
  func testSingleIndicatorOutputContainsOnlySelectedMetric() {
    let output = NotchHUDRenderOutputResolver.resolve(
      snapshot: .empty,
      configuration: .minimal)

    XCTAssertEqual(output.primary.metric, .cpu)
    XCTAssertEqual(output.primary.displayValue, "—")
    XCTAssertNil(output.secondary)
  }

  func testDualIndicatorOutputContainsIndependentSecondaryMetric() throws {
    var configuration = NotchHUDConfiguration.configuration(for: .cpu)
    configuration = NotchHUDConfigurationPolicy.settingIndicatorCount(.two, in: configuration)
    configuration = NotchHUDConfigurationPolicy.settingSecondaryMetric(
      .temperature,
      in: configuration)

    let output = NotchHUDRenderOutputResolver.resolve(
      snapshot: .empty,
      configuration: configuration)

    XCTAssertEqual(output.primary.metric, .cpu)
    XCTAssertEqual(try XCTUnwrap(output.secondary).metric, .temperature)
  }

  func testChangingSelectedMetricChangesOutputIdentityEvenWhenUnavailable() {
    let cpu = NotchHUDRenderOutputResolver.resolve(
      snapshot: .empty,
      configuration: .configuration(for: .cpu))
    let memory = NotchHUDRenderOutputResolver.resolve(
      snapshot: .empty,
      configuration: .configuration(for: .memory))

    XCTAssertNotEqual(cpu, memory)
  }

  func testEquivalentNormalizedConfigurationsProduceSameOutput() {
    var unnormalized = NotchHUDConfiguration.configuration(for: .cpu)
    unnormalized.lineThickness = 100
    unnormalized.warningThreshold = 95
    unnormalized.criticalThreshold = 80

    let normalized = NotchHUDConfigurationPolicy.normalized(unnormalized)
    XCTAssertEqual(
      NotchHUDRenderOutputResolver.resolve(
        snapshot: .empty,
        configuration: unnormalized),
      NotchHUDRenderOutputResolver.resolve(
        snapshot: .empty,
        configuration: normalized))
  }
}
