import XCTest

@testable import MacVitals

final class AlertPolicyTests: XCTestCase {
  func testHighMemoryEmitsOnlyOnTransition() {
    var policy = AlertPolicy(
      configuration: .init(memoryThresholdPercent: 90, cooldown: 60))
    let now = Date(timeIntervalSince1970: 1_000)
    let high = snapshot(memoryPercent: 95)

    XCTAssertEqual(policy.evaluate(snapshot: high, now: now).map(\.kind), [.highMemory])
    XCTAssertTrue(policy.evaluate(snapshot: high, now: now.addingTimeInterval(10)).isEmpty)
  }

  func testHighMemoryCanEmitAgainAfterRecoveryAndCooldown() {
    var policy = AlertPolicy(
      configuration: .init(memoryThresholdPercent: 90, cooldown: 60))
    let now = Date(timeIntervalSince1970: 2_000)

    XCTAssertEqual(policy.evaluate(snapshot: snapshot(memoryPercent: 95), now: now).count, 1)
    XCTAssertTrue(
      policy.evaluate(snapshot: snapshot(memoryPercent: 40), now: now.addingTimeInterval(10))
        .isEmpty)
    XCTAssertTrue(
      policy.evaluate(snapshot: snapshot(memoryPercent: 95), now: now.addingTimeInterval(30))
        .isEmpty)
    XCTAssertEqual(
      policy.evaluate(snapshot: snapshot(memoryPercent: 40), now: now.addingTimeInterval(70)).count,
      0)
    XCTAssertEqual(
      policy.evaluate(snapshot: snapshot(memoryPercent: 95), now: now.addingTimeInterval(71))
        .count,
      1)
  }

  func testClockRollbackDoesNotSuppressRecoveredAlert() {
    var policy = AlertPolicy(
      configuration: .init(memoryThresholdPercent: 90, cooldown: 60))
    let first = Date(timeIntervalSince1970: 1_000)

    XCTAssertEqual(
      policy.evaluate(snapshot: snapshot(memoryPercent: 95), now: first).map(\.kind),
      [.highMemory])
    XCTAssertTrue(
      policy.evaluate(snapshot: snapshot(memoryPercent: 40), now: first.addingTimeInterval(1))
        .isEmpty)

    let rolledBack = Date(timeIntervalSince1970: 900)
    XCTAssertEqual(
      policy.evaluate(snapshot: snapshot(memoryPercent: 95), now: rolledBack).map(\.kind),
      [.highMemory])
  }

  func testConfigurationUpdatePreservesActiveStateAndCooldown() {
    var policy = AlertPolicy(
      configuration: .init(memoryThresholdPercent: 90, cooldown: 60))
    let now = Date(timeIntervalSince1970: 3_000)

    XCTAssertEqual(
      policy.evaluate(snapshot: snapshot(memoryPercent: 95), now: now).map(\.kind),
      [.highMemory])

    policy.updateConfiguration(.init(memoryThresholdPercent: 100, cooldown: 60))
    XCTAssertTrue(
      policy.evaluate(snapshot: snapshot(memoryPercent: 95), now: now.addingTimeInterval(10))
        .isEmpty)

    policy.updateConfiguration(.init(memoryThresholdPercent: 90, cooldown: 60))
    XCTAssertTrue(
      policy.evaluate(snapshot: snapshot(memoryPercent: 95), now: now.addingTimeInterval(20))
        .isEmpty)

    XCTAssertTrue(
      policy.evaluate(snapshot: snapshot(memoryPercent: 40), now: now.addingTimeInterval(61))
        .isEmpty)
    XCTAssertEqual(
      policy.evaluate(snapshot: snapshot(memoryPercent: 95), now: now.addingTimeInterval(62))
        .map(\.kind),
      [.highMemory])
  }

  func testNativeMemoryPressureOverridesPercentageThreshold() {
    var policy = AlertPolicy(
      configuration: .init(memoryThresholdPercent: 95, cooldown: 0))

    let events = policy.evaluate(
      snapshot: snapshot(memoryPercent: 40, memoryPressure: .warning))

    XCTAssertEqual(events.map(\.kind), [.highMemory])
    XCTAssertEqual(events.first?.title, "Memory pressure warning")
  }

  func testCriticalMemoryPressureUsesCriticalMessage() {
    var policy = AlertPolicy(configuration: .init(memoryThresholdPercent: 95, cooldown: 0))

    let events = policy.evaluate(
      snapshot: snapshot(memoryPercent: 40, memoryPressure: .critical))

    XCTAssertEqual(events.first?.title, "Critical memory pressure")
    XCTAssertTrue(events.first?.message.contains("critical memory pressure") == true)
  }

  func testInsufficientPowerRequiresConfidence() {
    var policy = AlertPolicy(
      configuration: .init(powerConfidenceThreshold: 0.8, cooldown: 0))

    XCTAssertTrue(
      policy.evaluate(snapshot: snapshot(powerStatus: .insufficient, powerConfidence: 0.5))
        .isEmpty)
    XCTAssertEqual(
      policy.evaluate(snapshot: snapshot(powerStatus: .sufficient, powerConfidence: 1)).count,
      0)
    XCTAssertEqual(
      policy.evaluate(snapshot: snapshot(powerStatus: .insufficient, powerConfidence: 0.9))
        .map(\.kind),
      [.insufficientPower])
  }

  func testLowBatteryRequiresDischargingState() {
    var policy = AlertPolicy(configuration: .init(lowBatteryThresholdPercent: 15, cooldown: 0))

    XCTAssertTrue(
      policy.evaluate(snapshot: snapshot(batteryPercent: 10, batteryState: .charging)).isEmpty)
    XCTAssertEqual(
      policy.evaluate(snapshot: snapshot(batteryPercent: 10, batteryState: .discharging))
        .map(\.kind),
      [.lowBattery])
  }

  func testConfigurationUsesDefaultsForNonFiniteValues() {
    let configuration = AlertPolicyConfiguration(
      memoryThresholdPercent: .nan,
      lowBatteryThresholdPercent: .infinity,
      powerConfidenceThreshold: -.infinity,
      cooldown: .nan)

    XCTAssertEqual(
      configuration.memoryThresholdPercent,
      AlertPolicyConfiguration.defaultMemoryThresholdPercent)
    XCTAssertEqual(
      configuration.lowBatteryThresholdPercent,
      AlertPolicyConfiguration.defaultLowBatteryThresholdPercent)
    XCTAssertEqual(
      configuration.powerConfidenceThreshold,
      AlertPolicyConfiguration.defaultPowerConfidenceThreshold)
    XCTAssertEqual(configuration.cooldown, AlertPolicyConfiguration.defaultCooldown)
  }

  func testInvalidSnapshotNumbersDoNotEmitOrTrap() {
    var policy = AlertPolicy(configuration: .init(cooldown: 0))

    let events = policy.evaluate(
      snapshot: snapshot(
        memoryPercent: .infinity,
        batteryPercent: .nan,
        batteryState: .discharging,
        powerStatus: .insufficient,
        powerConfidence: .nan))

    XCTAssertTrue(events.isEmpty)
  }

  private func snapshot(
    memoryPercent: Double = 50,
    memoryPressure: MemoryPressureLevel = .normal,
    batteryPercent: Double = 80,
    batteryState: BatteryState = .charging,
    powerStatus: PowerSufficiencyStatus = .sufficient,
    powerConfidence: Double = 1
  ) -> SystemSnapshot {
    let now = Date(timeIntervalSince1970: 100)
    return SystemSnapshot(
      timestamp: now,
      cpu: .unavailable(unit: .percent),
      memory: MetricValue(
        value: MemoryStats(
          physicalBytes: 100,
          usedBytes: 50,
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
          pressureLevel: memoryPressure,
          usedPercent: memoryPercent),
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
          percentage: batteryPercent,
          state: batteryState,
          externalPowerConnected: batteryState != .discharging,
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
      adapter: .unavailable(unit: .watts),
      gpu: .unavailable(unit: .percent),
      power: MetricValue(
        value: PowerAssessment(
          status: powerStatus,
          confidence: powerConfidence,
          batteryPowerWatts: nil,
          estimatedSystemPowerWatts: nil,
          powerBalanceWatts: nil,
          explanation: "Power assessment"),
        unit: .watts,
        availability: .available,
        quality: .derived,
        source: .derivedPowerModel,
        timestamp: now,
        isEstimated: false,
        message: nil))
  }
}
