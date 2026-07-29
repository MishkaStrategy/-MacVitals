import AppKit
import XCTest
@testable import MacVitals

final class MenuBarStatusTitleRendererTests: XCTestCase {
  func testCompactPresentationRemovesLegacyLabelsEmojiAndUnits() {
    let text = MenuBarStatusTitleRenderer.compactText(
      snapshot: .empty,
      metrics: [.cpu, .gpu, .memory, .temperature, .battery, .fans, .systemPower])

    XCTAssertEqual(text, "—   —   —   —   —   —   —")
    XCTAssertFalse(text.contains("CPU"))
    XCTAssertFalse(text.contains("GPU"))
    XCTAssertFalse(text.contains("RAM"))
    XCTAssertFalse(text.contains("RPM"))
    XCTAssertFalse(text.contains("🌡"))
    XCTAssertFalse(text.contains("🔋"))
    XCTAssertFalse(text.contains("⚡"))
  }

  func testCoreMetricIconsKeepAStableMinimalSilhouetteAcrossStates() {
    let metrics: [MenuMetric] = [.cpu, .gpu, .memory, .fans, .systemPower]

    for metric in metrics {
      let preferredSymbols = Set(
        MenuBarIconState.allCases.compactMap {
          MenuBarIconCatalog.minimalSymbolCandidates(for: metric, state: $0).first
        })

      XCTAssertEqual(preferredSymbols.count, 1, "Expected a stable icon silhouette for \(metric)")
    }
  }

  func testPreferredMinimalSymbolsAvoidHeavyWarningTrianglesAndFillVariants() throws {
    let metrics: [MenuMetric] = [
      .battery, .cpu, .gpu, .memory, .temperature, .fans,
      .systemPower, .adapterPower, .powerStatus,
    ]

    for metric in metrics {
      for state in MenuBarIconState.allCases {
        let preferred = try XCTUnwrap(
          MenuBarIconCatalog.minimalSymbolCandidates(for: metric, state: state).first)
        XCTAssertFalse(preferred.contains("triangle"))
        XCTAssertFalse(preferred.hasSuffix(".fill"))
      }
    }
  }

  func testGPUAndAdapterUseDedicatedSymbolsWithCompatibleFallbacks() {
    XCTAssertEqual(
      MenuBarIconCatalog.minimalSymbolCandidates(for: .gpu, state: .normal),
      ["gpu", "display", "rectangle.3.group"])
    XCTAssertEqual(
      MenuBarIconCatalog.minimalSymbolCandidates(for: .adapterPower, state: .normal),
      ["powerplug", "bolt"])
  }

  @MainActor
  func testEveryMetricResolvesToAnImageOnTheTestRuntime() {
    for metric in MenuMetric.allCases {
      XCTAssertNotNil(
        MenuBarIconCatalog.minimalImage(for: metric, state: .normal),
        "Expected an available SF Symbol or fallback for \(metric)")
    }
  }

  @MainActor
  func testCompleteStatusSurfaceUsesNativeTemplateTinting() {
    let image = MenuBarStatusTitleRenderer.templateImage(
      snapshot: .empty,
      metrics: [.cpu, .gpu, .memory, .temperature, .battery, .fans])

    XCTAssertTrue(image.isTemplate)
    XCTAssertEqual(image.size.height, 18)
    XCTAssertGreaterThan(image.size.width, 12)
  }

  @MainActor
  func testTemplateSurfaceExpandsForAdditionalMetrics() {
    let singleMetric = MenuBarStatusTitleRenderer.templateImage(
      snapshot: .empty,
      metrics: [.cpu])
    let multipleMetrics = MenuBarStatusTitleRenderer.templateImage(
      snapshot: .empty,
      metrics: [.cpu, .gpu, .memory, .temperature, .battery, .fans])

    XCTAssertTrue(singleMetric.isTemplate)
    XCTAssertTrue(multipleMetrics.isTemplate)
    XCTAssertGreaterThan(multipleMetrics.size.width, singleMetric.size.width)
  }

  @MainActor
  func testEmptyMetricSelectionStillProducesAVisibleTemplateSymbol() {
    let image = MenuBarStatusTitleRenderer.templateImage(
      snapshot: .empty,
      metrics: [])

    XCTAssertTrue(image.isTemplate)
    XCTAssertGreaterThanOrEqual(image.size.width, 12)
    XCTAssertNotNil(image.tiffRepresentation)
  }
}
