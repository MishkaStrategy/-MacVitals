import Foundation
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

  func testMatchingStoredPresetRemainsSelected() {
    for preset in MenuPreset.allCases where preset != .custom {
      XCTAssertEqual(
        MenuPresetResolution.resolve(
          storedPreset: preset,
          metrics: preset.metrics,
          preserveExplicitCustom: true),
        preset)
    }
  }

  func testInterruptedPresetWriteInfersPresetFromStoredLayout() {
    XCTAssertEqual(
      MenuPresetResolution.resolve(
        storedPreset: .power,
        metrics: MenuPreset.performance.metrics,
        preserveExplicitCustom: true),
      .performance)
  }

  func testInterruptedCustomWriteInfersCustomFromStoredLayout() {
    XCTAssertEqual(
      MenuPresetResolution.resolve(
        storedPreset: .performance,
        metrics: [.cpu, .battery],
        preserveExplicitCustom: true),
      .custom)
  }

  func testExplicitCustomPresetIsPreservedForValidStoredLayout() {
    XCTAssertEqual(
      MenuPresetResolution.resolve(
        storedPreset: .custom,
        metrics: MenuPreset.performance.metrics,
        preserveExplicitCustom: true),
      .custom)
  }

  func testCustomWithoutStoredLayoutFallsBackToMatchingPreset() {
    XCTAssertEqual(
      MenuPresetResolution.resolve(
        storedPreset: .custom,
        metrics: MenuPreset.performance.metrics,
        preserveExplicitCustom: false),
      .performance)
  }

  func testUnknownLayoutResolvesToCustom() {
    XCTAssertEqual(
      MenuPresetResolution.resolve(
        storedPreset: .power,
        metrics: [.memory, .battery],
        preserveExplicitCustom: true),
      .custom)
  }

  func testCorrectionIsPersistedOnlyForValidStoredConfiguration() {
    XCTAssertTrue(
      MenuPresetResolution.shouldPersistCorrection(
        storedRawValue: MenuPreset.power.rawValue,
        resolvedPreset: .performance,
        hasValidStoredConfiguration: true))
    XCTAssertTrue(
      MenuPresetResolution.shouldPersistCorrection(
        storedRawValue: "futurePreset",
        resolvedPreset: .performance,
        hasValidStoredConfiguration: true))
    XCTAssertFalse(
      MenuPresetResolution.shouldPersistCorrection(
        storedRawValue: MenuPreset.performance.rawValue,
        resolvedPreset: .performance,
        hasValidStoredConfiguration: true))
    XCTAssertFalse(
      MenuPresetResolution.shouldPersistCorrection(
        storedRawValue: MenuPreset.power.rawValue,
        resolvedPreset: .performance,
        hasValidStoredConfiguration: false))
  }

  func testMenuConfigurationRoundTripNormalizesMetrics() throws {
    let encoded = try XCTUnwrap(
      MenuConfigurationPersistence.encode([.cpu, .memory, .cpu, .battery]))

    XCTAssertEqual(
      MenuConfigurationPersistence.decode(encoded),
      [.cpu, .memory, .battery])
  }

  func testMenuConfigurationRejectsUnsupportedSchemaVersions() {
    for version in [0, MenuConfigurationPersistence.currentSchemaVersion + 1, Int.max] {
      let data = Data(
        """
        {"schemaVersion":\(version),"enabledMetricIDs":["cpu","memory"]}
        """.utf8)
      XCTAssertNil(MenuConfigurationPersistence.decode(data))
    }
  }

  func testMenuConfigurationRejectsMalformedPayload() {
    XCTAssertNil(MenuConfigurationPersistence.decode(Data("not-json".utf8)))
    XCTAssertNil(
      MenuConfigurationPersistence.decode(
        Data("{\"schemaVersion\":1,\"enabledMetricIDs\":42}".utf8)))
  }

  func testCurrentSchemaIgnoresUnknownMetricIdentifiers() {
    let data = Data(
      """
      {"schemaVersion":1,"enabledMetricIDs":["cpu","futureMetric","cpu","battery"]}
      """.utf8)

    XCTAssertEqual(MenuConfigurationPersistence.decode(data), [.cpu, .battery])
  }
}
