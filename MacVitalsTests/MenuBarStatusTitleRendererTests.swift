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
  func testDarkMenuBarAppearanceUsesLightForeground() throws {
    let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
    let color = MenuBarStatusTitleRenderer.statusBarForegroundColor(for: appearance)
    let rgb = try XCTUnwrap(color.usingColorSpace(.deviceRGB))

    XCTAssertGreaterThan(rgb.redComponent, 0.9)
    XCTAssertGreaterThan(rgb.greenComponent, 0.9)
    XCTAssertGreaterThan(rgb.blueComponent, 0.9)
    XCTAssertGreaterThan(rgb.alphaComponent, 0.9)
  }

  @MainActor
  func testDarkMenuBarAttachmentsArePreTintedInsteadOfTemplateBlack() throws {
    let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
    let title = MenuBarStatusTitleRenderer.attributedTitle(
      snapshot: .empty,
      metrics: [.cpu, .temperature, .fans, .battery],
      appearance: appearance)
    var images: [NSImage] = []

    title.enumerateAttribute(
      .attachment,
      in: NSRange(location: 0, length: title.length)
    ) { value, _, _ in
      guard let attachment = value as? NSTextAttachment,
        let image = attachment.image
      else { return }
      images.append(image)
    }

    XCTAssertEqual(images.count, 4)
    XCTAssertTrue(images.allSatisfy { !$0.isTemplate })
  }
}
