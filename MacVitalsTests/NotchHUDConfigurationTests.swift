import Foundation
import XCTest
@testable import MacVitals

final class NotchHUDConfigurationTests: XCTestCase {
  func testBalancedConfigurationMatchesCurrentCompactHUD() {
    let configuration = NotchHUDConfigurationPolicy.normalized(.balanced)

    XCTAssertEqual(configuration.metrics(for: .left), [.cpu, .gpu, .memory])
    XCTAssertEqual(
      configuration.metrics(for: .right),
      [.fans, .temperature, .battery, .systemPower])
    XCTAssertTrue(configuration.showLeftPanel)
    XCTAssertTrue(configuration.showRightPanel)
  }

  func testNormalizationRemovesDuplicatesAndCrossPanelConflicts() {
    var configuration = NotchHUDConfiguration.balanced
    configuration.leftMetrics = [.cpu, .cpu, .memory]
    configuration.rightMetrics = [.cpu, .battery, .battery]
    configuration.leftVisibleCount = 99
    configuration.rightVisibleCount = 0
    configuration.backgroundOpacity = 3

    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)

    XCTAssertEqual(normalized.leftMetrics, [.cpu, .memory])
    XCTAssertEqual(normalized.rightMetrics, [.battery])
    XCTAssertEqual(normalized.leftVisibleCount, 2)
    XCTAssertEqual(normalized.rightVisibleCount, 1)
    XCTAssertEqual(normalized.backgroundOpacity, 0.95, accuracy: 0.001)
  }

  func testRemovingLastMetricHidesItsPanel() {
    var configuration = NotchHUDConfiguration.minimal
    configuration.leftMetrics = [.cpu]
    configuration.leftVisibleCount = 1

    let result = NotchHUDConfigurationPolicy.setting(
      .cpu,
      side: nil,
      in: configuration)

    XCTAssertTrue(result.leftMetrics.isEmpty)
    XCTAssertFalse(result.showLeftPanel)
    XCTAssertEqual(result.metrics(for: .left), [])
  }

  func testMovingMetricChangesOnlyItsPanelOrder() {
    let result = NotchHUDConfigurationPolicy.moving(
      .memory,
      towardStart: true,
      in: .balanced)

    XCTAssertEqual(result.leftMetrics, [.cpu, .memory, .gpu])
    XCTAssertEqual(
      result.rightMetrics,
      NotchHUDConfiguration.balanced.rightMetrics)
  }

  func testPresetResolutionBecomesCustomAfterAppearanceChange() {
    XCTAssertEqual(
      NotchHUDConfigurationPolicy.resolvedPreset(for: .detailed),
      .detailed)

    var configuration = NotchHUDConfiguration.detailed
    configuration.showLabels = false
    XCTAssertEqual(
      NotchHUDConfigurationPolicy.resolvedPreset(for: configuration),
      .custom)
  }

  func testPersistenceRoundTripKeepsNormalizedConfiguration() throws {
    var configuration = NotchHUDConfiguration.detailed
    configuration.leftVisibleCount = 2
    configuration.backgroundOpacity = 0.4
    configuration.hideUnavailableMetrics = true

    let data = try XCTUnwrap(NotchHUDConfigurationPersistence.encode(configuration))
    let decoded = try XCTUnwrap(NotchHUDConfigurationPersistence.decode(data))

    XCTAssertEqual(
      decoded,
      NotchHUDConfigurationPolicy.normalized(configuration))
  }

  func testInvalidPersistencePayloadIsRejected() {
    XCTAssertNil(NotchHUDConfigurationPersistence.decode(Data("not json".utf8)))
  }
}