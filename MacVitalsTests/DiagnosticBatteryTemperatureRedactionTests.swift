import XCTest
@testable import MacVitals

final class DiagnosticBatteryTemperatureRedactionTests: XCTestCase {
  func testDiagnosticRedactorPreservesTemperatureBoundaries() {
    XCTAssertEqual(redactedTemperature(-20), -20)
    XCTAssertEqual(redactedTemperature(100), 100)
  }

  func testDiagnosticRedactorOmitsInvalidTemperatures() {
    for value in [-20.01, 100.01, Double.nan, .infinity, -.infinity] {
      XCTAssertNil(redactedTemperature(value))
    }
  }

  private func redactedTemperature(_ temperature: Double) -> Double? {
    let now = Date(timeIntervalSince1970: 100)
    let battery = MetricValue(
      value: BatteryStats(
        present: true,
        percentage: 50,
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
        temperatureCelsius: temperature,
        voltageVolts: nil,
        currentAmperes: nil,
        batteryPowerWatts: nil),
      unit: .percent,
      availability: .available,
      quality: .experimental,
      source: .iokitRegistry,
      timestamp: now,
      isEstimated: false,
      message: nil)

    let snapshot = SystemSnapshot(
      timestamp: now,
      cpu: .unavailable(unit: .percent, availability: .temporarilyUnavailable),
      memory: .unavailable(unit: .bytes, availability: .temporarilyUnavailable),
      battery: battery,
      adapter: .unavailable(unit: .watts, availability: .temporarilyUnavailable),
      gpu: .unavailable(unit: .percent, availability: .temporarilyUnavailable),
      power: .unavailable(unit: .watts, availability: .temporarilyUnavailable))

    return DiagnosticSnapshotRedactor.redact(snapshot).battery.value?.temperatureCelsius
  }
}
