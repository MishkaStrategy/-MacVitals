import XCTest
@testable import MacVitals

final class MenuBarRendererTests: XCTestCase {
  func testEmptyMetricsUseCompactFallback() {
    XCTAssertEqual(MenuBarRenderer.render(snapshot: .empty, metrics: []), "◉")
  }

  func testUnavailableMetricsRemainVisible() {
    XCTAssertEqual(
      MenuBarRenderer.render(snapshot: .empty, metrics: [.cpu, .gpu, .memory]),
      "CPU — · GPU — · RAM —")
  }

  func testDuplicateMetricsAreRemoved() {
    XCTAssertEqual(
      MenuBarRenderer.render(snapshot: .empty, metrics: [.cpu, .cpu]),
      "CPU —")
  }

  func testLongTextIsTruncatedDeterministically() {
    let rendered = MenuBarRenderer.render(
      snapshot: .empty,
      metrics: MenuMetric.allCases,
      maximumCharacters: 12)

    XCTAssertEqual(rendered.count, 12)
    XCTAssertTrue(rendered.hasSuffix("…"))
  }
}
