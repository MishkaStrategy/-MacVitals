import XCTest
@testable import MacVitals

final class SystemPowerAssessmentResolverTests: XCTestCase {
  func testDerivesSystemPowerFromBatteryDischargeWhenUnplugged() {
    let assessment = PowerAssessment(
      status: .notConnected,
      confidence: 1,
      batteryPowerWatts: -18.75,
      estimatedSystemPowerWatts: nil,
      powerBalanceWatts: nil,
      explanation: "On battery")

    let resolved = SystemPowerAssessmentResolver.resolve(
      assessment: assessment,
      battery: battery(powerWatts: -18.75),
      externalPowerState: .disconnected)

    XCTAssertEqual(resolved.estimatedSystemPowerWatts, 18.75)
  }

  func testDoesNotClaimTotalSystemPowerWhileConnectedWithoutAdapterMeasurement() {
    let assessment = PowerAssessment(
      status: .chargingBattery,
      confidence: 1,
      batteryPowerWatts: 12,
      estimatedSystemPowerWatts: nil,
      powerBalanceWatts: nil,
      explanation: "Charging")

    let resolved = SystemPowerAssessmentResolver.resolve(
      assessment: assessment,
      battery: battery(powerWatts: 12),
      externalPowerState: .connected)

    XCTAssertNil(resolved.estimatedSystemPowerWatts)
  }

  private func battery(powerWatts: Double) -> BatteryStats {
    BatteryStats(
      present: true,
      percentage: 75,
      state: .discharging,
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
      batteryPowerWatts: powerWatts)
  }
}
