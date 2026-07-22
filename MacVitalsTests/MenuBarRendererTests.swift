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

  func testZeroAndOneCharacterLimitsAreHonored() {
    XCTAssertEqual(
      MenuBarRenderer.render(snapshot: .empty, metrics: [.cpu], maximumCharacters: 0),
      "")
    XCTAssertEqual(
      MenuBarRenderer.render(snapshot: .empty, metrics: [.cpu], maximumCharacters: 1),
      "…")
  }

  func testInvalidNumericMetricsUseUnavailablePlaceholders() {
    XCTAssertEqual(
      MenuBarRenderer.render(snapshot: invalidNumericSnapshot(), metrics: MenuMetric.allCases),
      "CPU — · GPU — · RAM — · 🔋 — · ⚡ — · ?")
  }

  private func invalidNumericSnapshot() -> SystemSnapshot {
    let now = Date(timeIntervalSince1970: 100)
    return SystemSnapshot(
      timestamp: now,
      cpu: MetricValue(
        value: CPUStats(
          total: .nan,
          user: 0,
          system: 0,
          idle: 0,
          logicalProcessors: 1,
          activeProcessors: 1),
        unit: .percent,
        availability: .available,
        quality: .direct,
        source: .machHostStatistics,
        timestamp: now,
        isEstimated: false,
        message: nil),
      memory: MetricValue(
        value: MemoryStats(
          physicalBytes: 1,
          usedBytes: 1,
          freeBytes: 0,
          availableBytes: 0,
          activeBytes: 0,
          inactiveBytes: 0,
          wiredBytes: 0,
          compressedBytes: 0,
          purgeableBytes: 0,
          speculativeBytes: 0,
          swapTotalBytes: nil,
          swapUsedBytes: nil,
          swapFreeBytes: nil,
          pressureLevel: .unknown,
          usedPercent: .infinity),
        unit: .bytes,
        availability: .available,
        quality: .derived,
        source: .machHostStatistics,
        timestamp: now,
        isEstimated: false,
        message: nil),
      battery: MetricValue(
        value: BatteryStats(
          present: true,
          percentage: -1,
          state: .unknown,
          externalPowerConnected: false,
          timeRemainingMinutes: nil,
          timeToFullMinutes: nil,
          cycleCount: nil,
          condition: nil,
          currentCapacityMah: nil,
          maxCapacityMah: nil,
          designCapacityMah: nil,
          healthPercent: nil,
          temperatureCelsius: nil,
          voltageVolts: nil,
          currentAmperes: nil,
          batteryPowerWatts: nil),
        unit: .percent,
        availability: .available,
        quality: .direct,
        source: .iokitPowerSources,
        timestamp: now,
        isEstimated: false,
        message: nil),
      adapter: MetricValue(
        value: AdapterStats(
          connected: true,
          manufacturer: nil,
          model: nil,
          transport: nil,
          ratedPowerWatts: .nan,
          voltageVolts: nil,
          currentAmperes: nil,
          measuredPowerWatts: nil),
        unit: .watts,
        availability: .available,
        quality: .direct,
        source: .iokitPowerSources,
        timestamp: now,
        isEstimated: false,
        message: nil),
      gpu: MetricValue(
        value: GPUStats(
          name: nil,
          metalAvailable: false,
          registryID: nil,
          hasUnifiedMemory: nil,
          isLowPower: nil,
          isRemovable: nil,
          recommendedWorkingSetBytes: nil,
          systemUtilizationPercent: .infinity,
          utilizationAvailability: .available),
        unit: .percent,
        availability: .available,
        quality: .direct,
        source: .metal,
        timestamp: now,
        isEstimated: false,
        message: nil),
      power: .unavailable(unit: .watts, availability: .temporarilyUnavailable))
  }
}