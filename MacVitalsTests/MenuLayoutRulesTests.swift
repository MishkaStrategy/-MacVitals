import XCTest

@testable import MacVitals

final class MenuLayoutRulesTests: XCTestCase {
  func testNormalizationPreservesFirstOccurrenceOrder() {
    XCTAssertEqual(
      MenuLayoutRules.normalized([.cpu, .memory, .cpu, .battery, .memory]),
      [.cpu, .memory, .battery]
    )
  }

  func testMetricCanBeHiddenAndRestored() {
    let hidden = MenuLayoutRules.setting(
      .gpu,
      enabled: false,
      in: [.cpu, .gpu, .memory]
    )
    XCTAssertEqual(hidden, [.cpu, .memory])

    let restored = MenuLayoutRules.setting(.gpu, enabled: true, in: hidden)
    XCTAssertEqual(restored, [.cpu, .memory, .gpu])
  }

  func testEnablingAnExistingMetricDoesNotDuplicateIt() {
    XCTAssertEqual(
      MenuLayoutRules.setting(.cpu, enabled: true, in: [.cpu, .memory]),
      [.cpu, .memory]
    )
  }

  func testPresetsHaveUniqueMetrics() {
    for preset in MenuPreset.allCases where preset != .custom {
      XCTAssertEqual(preset.metrics, MenuLayoutRules.normalized(preset.metrics))
    }
  }
}
