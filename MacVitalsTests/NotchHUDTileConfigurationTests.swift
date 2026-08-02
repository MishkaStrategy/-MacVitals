import Foundation
import XCTest
@testable import MacVitals

final class NotchHUDTileConfigurationTests: XCTestCase {
  func testEveryMetricReceivesAnIndependentDefaultTile() {
    let configuration = NotchHUDConfigurationPolicy.normalized(.balanced)

    XCTAssertEqual(configuration.tileConfigurations.count, MenuMetric.allCases.count)
    for metric in MenuMetric.allCases {
      XCTAssertEqual(
        configuration.tileConfiguration(for: metric),
        NotchHUDTileConfiguration.defaultConfiguration(for: metric))
    }
  }

  func testTileNormalizationClampsLabelOpacityAndThresholdOrder() {
    var tile = NotchHUDTileConfiguration.defaultConfiguration(for: .temperature)
    tile.customLabel = "  VERY-LONG-TEMPERATURE-LABEL  "
    tile.symbolName = "   "
    tile.backgroundOpacity = 3
    tile.warningThreshold = 95
    tile.criticalThreshold = 70

    let normalized = NotchHUDTileConfigurationPolicy.normalized(tile, for: .temperature)

    XCTAssertEqual(normalized.customLabel, "VERY-LONG-TE")
    XCTAssertEqual(normalized.symbolName, MenuMetric.temperature.defaultSymbol)
    XCTAssertEqual(normalized.backgroundOpacity, 1, accuracy: 0.001)
    XCTAssertEqual(normalized.warningThreshold, 70, accuracy: 0.001)
    XCTAssertEqual(normalized.criticalThreshold, 95, accuracy: 0.001)
  }

  func testValueFormatterCanHideUnitAndApplyPrecision() {
    var tile = NotchHUDTileConfiguration.defaultConfiguration(for: .temperature)
    tile.precision = .zero
    tile.showsUnit = false

    XCTAssertEqual(
      NotchHUDTileValueFormatter.renderedValue(from: "72.6 °C", configuration: tile),
      "73")

    tile.showsUnit = true
    XCTAssertEqual(
      NotchHUDTileValueFormatter.renderedValue(from: "72.6 °C", configuration: tile),
      "73 °C")
  }

  func testSemanticThresholdsSupportHighAndLowCriticalMetrics() {
    let temperature = NotchHUDTileConfiguration.defaultConfiguration(for: .temperature)
    switch NotchHUDTileConfigurationPolicy.semanticState(
      renderedValue: "91 °C",
      configuration: temperature)
    {
    case .critical: break
    default: XCTFail("Expected critical high temperature")
    }

    let battery = NotchHUDTileConfiguration.defaultConfiguration(for: .battery)
    switch NotchHUDTileConfigurationPolicy.semanticState(
      renderedValue: "18%",
      configuration: battery)
    {
    case .warning: break
    default: XCTFail("Expected low-battery warning")
    }
  }

  func testLegacySchemaMigratesToTileProfiles() throws {
    let legacy = """
    {
      "schemaVersion": 1,
      "configuration": {
        "leftMetrics": ["cpu", "memory"],
        "rightMetrics": ["temperature", "battery"],
        "leftVisibleCount": 2,
        "rightVisibleCount": 2,
        "showLeftPanel": true,
        "showRightPanel": true,
        "density": "compact",
        "textSize": "small",
        "backgroundOpacity": 0.52,
        "showLabels": false,
        "showSeparators": false,
        "hideUnavailableMetrics": true,
        "showOnDisplaysWithoutNotch": false
      }
    }
    """

    let decoded = try XCTUnwrap(
      NotchHUDConfigurationPersistence.decode(Data(legacy.utf8)))

    XCTAssertEqual(decoded.metrics(for: .left), [.cpu, .memory])
    XCTAssertEqual(decoded.metrics(for: .right), [.temperature, .battery])
    XCTAssertEqual(decoded.tileConfigurations.count, MenuMetric.allCases.count)
    XCTAssertEqual(decoded.tileConfiguration(for: .battery).thresholdDirection, .lowIsCritical)
  }

  func testWideTileExpandsOnlyItsPanel() {
    let base = NotchHUDConfigurationPolicy.normalized(.balanced)
    let baseLeftWidth = NotchHUDLayout.preferredPanelWidth(
      metrics: base.metrics(for: .left),
      configuration: base)
    let baseRightWidth = NotchHUDLayout.preferredPanelWidth(
      metrics: base.metrics(for: .right),
      configuration: base)

    var cpuTile = base.tileConfiguration(for: .cpu)
    cpuTile.size = .wide
    let customized = NotchHUDConfigurationPolicy.settingTile(cpuTile, for: .cpu, in: base)

    XCTAssertEqual(
      NotchHUDLayout.preferredPanelWidth(
        metrics: customized.metrics(for: .left),
        configuration: customized),
      baseLeftWidth + 30,
      accuracy: 0.001)
    XCTAssertEqual(
      NotchHUDLayout.preferredPanelWidth(
        metrics: customized.metrics(for: .right),
        configuration: customized),
      baseRightWidth,
      accuracy: 0.001)
  }

  func testPersistenceKeepsIndividualTileSettings() throws {
    var tile = NotchHUDTileConfiguration.defaultConfiguration(for: .cpu)
    tile.contentStyle = .valueOnly
    tile.size = .wide
    tile.colorMode = .semantic
    tile.backgroundStyle = .outline
    tile.customLabel = "CORE"

    let customized = NotchHUDConfigurationPolicy.settingTile(tile, for: .cpu, in: .balanced)
    let data = try XCTUnwrap(NotchHUDConfigurationPersistence.encode(customized))
    let decoded = try XCTUnwrap(NotchHUDConfigurationPersistence.decode(data))

    XCTAssertEqual(decoded.tileConfiguration(for: .cpu).contentStyle, .valueOnly)
    XCTAssertEqual(decoded.tileConfiguration(for: .cpu).size, .wide)
    XCTAssertEqual(decoded.tileConfiguration(for: .cpu).colorMode, .semantic)
    XCTAssertEqual(decoded.tileConfiguration(for: .cpu).backgroundStyle, .outline)
    XCTAssertEqual(decoded.tileConfiguration(for: .cpu).customLabel, "CORE")
  }
}
