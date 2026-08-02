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
  func testCompleteStatusSurfaceContainsOnlyWhiteOpaquePixels() throws {
    let image = MenuBarStatusTitleRenderer.lightImage(
      snapshot: .empty,
      metrics: [.cpu, .gpu, .memory, .temperature, .battery, .fans])

    XCTAssertFalse(image.isTemplate)
    XCTAssertEqual(image.size.height, 18)
    XCTAssertGreaterThan(image.size.width, 12)

    let representation = try bitmapRepresentation(of: image)
    let statistics = try opaquePixelStatistics(in: representation)

    XCTAssertGreaterThan(statistics.count, 100)
    XCTAssertGreaterThan(
      statistics.minimumRGB,
      0.92,
      "Every visible icon and value pixel must be physically white")
  }

  @MainActor
  func testSingleMetricValuePixelsCannotRemainBlack() throws {
    let image = MenuBarStatusTitleRenderer.lightImage(
      snapshot: .empty,
      metrics: [.cpu])
    let representation = try bitmapRepresentation(of: image)
    let statistics = try opaquePixelStatistics(in: representation)

    XCTAssertGreaterThan(statistics.count, 20)
    XCTAssertGreaterThan(
      statistics.minimumRGB,
      0.92,
      "The compact value glyph must be recolored together with its icon")
  }

  @MainActor
  func testLightSurfaceExpandsForAdditionalMetrics() {
    let singleMetric = MenuBarStatusTitleRenderer.lightImage(
      snapshot: .empty,
      metrics: [.cpu])
    let multipleMetrics = MenuBarStatusTitleRenderer.lightImage(
      snapshot: .empty,
      metrics: [.cpu, .gpu, .memory, .temperature, .battery, .fans])

    XCTAssertFalse(singleMetric.isTemplate)
    XCTAssertFalse(multipleMetrics.isTemplate)
    XCTAssertGreaterThan(multipleMetrics.size.width, singleMetric.size.width)
  }

  @MainActor
  func testEmptyMetricSelectionStillProducesAVisibleWhiteSymbol() throws {
    let image = MenuBarStatusTitleRenderer.lightImage(
      snapshot: .empty,
      metrics: [])

    XCTAssertFalse(image.isTemplate)
    XCTAssertGreaterThanOrEqual(image.size.width, 12)

    let representation = try bitmapRepresentation(of: image)
    let statistics = try opaquePixelStatistics(in: representation)
    XCTAssertGreaterThan(statistics.count, 0)
    XCTAssertGreaterThan(statistics.minimumRGB, 0.92)
  }

  private func bitmapRepresentation(of image: NSImage) throws -> NSBitmapImageRep {
    let data = try XCTUnwrap(image.tiffRepresentation)
    return try XCTUnwrap(NSBitmapImageRep(data: data))
  }

  private func opaquePixelStatistics(
    in representation: NSBitmapImageRep
  ) throws -> (count: Int, minimumRGB: CGFloat) {
    var count = 0
    var minimumRGB: CGFloat = 1

    for y in 0..<representation.pixelsHigh {
      for x in 0..<representation.pixelsWide {
        guard
          let color = representation.colorAt(x: x, y: y),
          color.alphaComponent > 0.8,
          let rgb = color.usingColorSpace(.deviceRGB)
        else {
          continue
        }

        count += 1
        minimumRGB = min(
          minimumRGB,
          rgb.redComponent,
          rgb.greenComponent,
          rgb.blueComponent)
      }
    }

    guard count > 0 else {
      XCTFail("Expected at least one mostly opaque status-bar pixel")
      throw NSError(domain: "MenuBarStatusTitleRendererTests", code: 1)
    }

    return (count, minimumRGB)
  }
}
