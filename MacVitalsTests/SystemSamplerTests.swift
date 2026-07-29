import XCTest

@testable import MacVitals

final class SystemSamplerTests: XCTestCase {
  func testSamplerProducesCoherentHardwareSnapshotAndTimings() async throws {
    let sampler = SystemSampler()
    let firstResult = await sampler.sample()
    try await Task.sleep(nanoseconds: 100_000_000)
    let secondResult = await sampler.sample()
    let first = firstResult.snapshot
    let second = secondResult.snapshot

    XCTAssertGreaterThanOrEqual(second.timestamp, first.timestamp)
    XCTAssertEqual(second.memory.availability, .available)
    XCTAssertGreaterThan(second.memory.value?.physicalBytes ?? 0, 0)
    XCTAssertLessThanOrEqual(second.memory.value?.usedPercent ?? 101, 100)
    XCTAssertNotEqual(second.cpu.availability, .providerError)
    XCTAssertNotEqual(second.gpu.availability, .providerError)
    XCTAssertNotNil(second.power.value)
    if second.battery.value?.present == false {
      XCTAssertEqual(second.power.value?.status, .powerAdapterOnly)
    }
    XCTAssertGreaterThanOrEqual(secondResult.timings.totalMilliseconds, 0)
    XCTAssertGreaterThanOrEqual(secondResult.timings.cpuMilliseconds, 0)
    XCTAssertGreaterThanOrEqual(secondResult.timings.memoryMilliseconds, 0)

    let maximumSkew: TimeInterval = 5
    XCTAssertLessThan(abs(second.timestamp.timeIntervalSince(second.memory.timestamp)), maximumSkew)
    XCTAssertLessThan(abs(second.timestamp.timeIntervalSince(second.power.timestamp)), maximumSkew)
  }

  func testLaptopBatterySignalRemainsAuthoritative() {
    XCTAssertEqual(
      ExternalPowerResolver.resolve(
        battery: battery(present: true, externalPower: false),
        batteryAvailability: .available,
        adapter: adapter(connected: true),
        adapterAvailability: .available),
      .disconnected)
    XCTAssertEqual(
      ExternalPowerResolver.resolve(
        battery: battery(present: true, externalPower: true),
        batteryAvailability: .available,
        adapter: adapter(connected: false),
        adapterAvailability: .available),
      .connected)
  }

  func testBatterylessMacIsKnownToUseExternalPowerWithoutAdapterTelemetry() {
    XCTAssertEqual(
      ExternalPowerResolver.resolve(
        battery: battery(present: false, externalPower: false),
        batteryAvailability: .unsupported,
        adapter: nil,
        adapterAvailability: .temporarilyUnavailable),
      .connected)
  }

  func testUnavailableBatteryFallsBackOnlyToAvailableAdapterSignal() {
    XCTAssertEqual(
      ExternalPowerResolver.resolve(
        battery: nil,
        batteryAvailability: .providerError,
        adapter: adapter(connected: true),
        adapterAvailability: .available),
      .connected)
    XCTAssertEqual(
      ExternalPowerResolver.resolve(
        battery: nil,
        batteryAvailability: .providerError,
        adapter: adapter(connected: false),
        adapterAvailability: .available),
      .disconnected)
  }

  func testUnavailablePowerProvidersResolveToUnknown() {
    XCTAssertEqual(
      ExternalPowerResolver.resolve(
        battery: nil,
        batteryAvailability: .providerError,
        adapter: nil,
        adapterAvailability: .temporarilyUnavailable),
      .unknown)
    XCTAssertEqual(
      ExternalPowerResolver.resolve(
        battery: nil,
        batteryAvailability: .providerError,
        adapter: adapter(connected: true),
        adapterAvailability: .providerError),
      .unknown)
  }

  func testInconsistentBatteryAvailabilityDoesNotCreateFalsePowerClaim() {
    XCTAssertEqual(
      ExternalPowerResolver.resolve(
        battery: battery(present: true, externalPower: false),
        batteryAvailability: .providerError,
        adapter: adapter(connected: true),
        adapterAvailability: .available),
      .unknown)
    XCTAssertEqual(
      ExternalPowerResolver.resolve(
        battery: battery(present: false, externalPower: false),
        batteryAvailability: .available,
        adapter: adapter(connected: true),
        adapterAvailability: .available),
      .unknown)
  }

  func testUnknownPowerStateProducesUnavailableAssessmentOnlyForUnknown() throws {
    let assessment = try XCTUnwrap(UnknownExternalPowerAssessment.make(for: .unknown))
    XCTAssertEqual(assessment.status, .unknown)
    XCTAssertEqual(assessment.confidence, 0)
    XCTAssertFalse(assessment.explanation.isEmpty)
    XCTAssertNil(UnknownExternalPowerAssessment.make(for: .connected))
    XCTAssertNil(UnknownExternalPowerAssessment.make(for: .disconnected))
  }

  func testBatterylessMacUsesAdapterOnlyAssessmentWithoutAdapterTelemetry() throws {
    let assessment = try XCTUnwrap(
      BatterylessPowerAssessment.make(
        battery: battery(present: false, externalPower: false)))

    XCTAssertEqual(assessment.status, .powerAdapterOnly)
    XCTAssertEqual(assessment.confidence, 1)
    XCTAssertNil(assessment.batteryPowerWatts)
    XCTAssertNil(assessment.estimatedSystemPowerWatts)
    XCTAssertFalse(assessment.explanation.isEmpty)
  }

  func testBatterylessAssessmentDoesNotMaskAvailableOrFailedBatteryProvider() {
    XCTAssertNil(
      BatterylessPowerAssessment.make(
        battery: battery(present: true, externalPower: true)))
    XCTAssertNil(BatterylessPowerAssessment.make(battery: nil))
  }

  private func battery(present: Bool, externalPower: Bool) -> BatteryStats {
    BatteryStats(
      present: present,
      percentage: present ? 50 : nil,
      state: present ? (externalPower ? .adapterPower : .discharging) : .absent,
      externalPowerConnected: externalPower,
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
      batteryPowerWatts: nil)
  }

  private func adapter(connected: Bool) -> AdapterStats {
    AdapterStats(
      connected: connected,
      manufacturer: nil,
      model: nil,
      transport: nil,
      ratedPowerWatts: connected ? 67 : nil,
      voltageVolts: nil,
      currentAmperes: nil,
      measuredPowerWatts: nil)
  }
}
