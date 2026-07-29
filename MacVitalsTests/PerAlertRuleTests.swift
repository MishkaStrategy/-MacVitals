import XCTest

@testable import MacVitals

final class PerAlertRuleTests: XCTestCase {
  func testDisabledMemoryRuleSuppressesPercentageAndPressureAlerts() {
    var policy = AlertPolicy(
      configuration: .init(
        memoryAlertsEnabled: false,
        lowBatteryAlertsEnabled: true,
        memoryThresholdPercent: 50,
        cooldown: 0))

    let events = policy.evaluate(
      snapshot: snapshot(
        memoryPercent: 99,
        memoryPressure: .critical,
        batteryPercent: 80,
        batteryState: .charging))

    XCTAssertFalse(events.contains { $0.kind == .highMemory })
  }

  func testDisabledBatteryRuleSuppressesLowBatteryAlert() {
    var policy = AlertPolicy(
      configuration: .init(
        memoryAlertsEnabled: true,
        lowBatteryAlertsEnabled: false,
        lowBatteryThresholdPercent: 50,
        cooldown: 0))

    let events = policy.evaluate(
      snapshot: snapshot(
        memoryPercent: 40,
        memoryPressure: .normal,
        batteryPercent: 5,
        batteryState: .discharging))

    XCTAssertFalse(events.contains { $0.kind == .lowBattery })
  }

  func testReenabledRuleCanEmitWithoutWaitingForAnotherAppLaunch() {
    var policy = AlertPolicy(
      configuration: .init(memoryAlertsEnabled: false, cooldown: 0))
    let highMemory = snapshot(
      memoryPercent: 95,
      memoryPressure: .normal,
      batteryPercent: 80,
      batteryState: .charging)

    XCTAssertTrue(policy.evaluate(snapshot: highMemory).isEmpty)
    policy.updateConfiguration(.init(memoryAlertsEnabled: true, cooldown: 0))
    XCTAssertEqual(policy.evaluate(snapshot: highMemory).map(\.kind), [.highMemory])
  }

  private func snapshot(
    memoryPercent: Double,
    memoryPressure: MemoryPressureLevel,
    batteryPercent: Double,
    batteryState: BatteryState
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
          status: .sufficient,
          confidence: 1,
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
