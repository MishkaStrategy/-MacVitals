import XCTest
@testable import MacVitals

final class MenuBarIconCatalogTests: XCTestCase {
  func testEveryRequestedCategoryHasThreeDistinctTemplateVariants() {
    let metrics: [MenuMetric] = [
      .battery, .cpu, .memory, .gpu, .temperature, .systemPower, .fans,
    ]

    for metric in metrics {
      let symbols = Set(
        MenuBarIconState.allCases.map {
          MenuBarIconCatalog.symbolName(for: metric, state: $0)
        })
      XCTAssertEqual(symbols.count, 3, "Expected three distinct icon states for \(metric)")
    }
  }

  func testPowerMetricsShareTheSameNativeIconLanguage() {
    for state in MenuBarIconState.allCases {
      XCTAssertEqual(
        MenuBarIconCatalog.symbolName(for: .systemPower, state: state),
        MenuBarIconCatalog.symbolName(for: .adapterPower, state: state))
      XCTAssertEqual(
        MenuBarIconCatalog.symbolName(for: .systemPower, state: state),
        MenuBarIconCatalog.symbolName(for: .powerStatus, state: state))
    }
  }
}
