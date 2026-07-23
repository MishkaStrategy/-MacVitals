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
    XCTAssertGreaterThanOrEqual(secondResult.timings.totalMilliseconds, 0)
    XCTAssertGreaterThanOrEqual(secondResult.timings.cpuMilliseconds, 0)
    XCTAssertGreaterThanOrEqual(secondResult.timings.memoryMilliseconds, 0)

    let maximumSkew: TimeInterval = 5
    XCTAssertLessThan(abs(second.timestamp.timeIntervalSince(second.memory.timestamp)), maximumSkew)
    XCTAssertLessThan(abs(second.timestamp.timeIntervalSince(second.power.timestamp)), maximumSkew)
  }

  func testLaptopBatterySignalRemainsAuthoritative() {
    XCTAssertFalse(
      ExternalPowerResolver.isConnected(
        battery: battery(present: true, externalPower: false),
        adapter: adapter(connected: true)))
    XCTAssertTrue(
      ExternalPowerResolver.isConnected(
        battery: battery(present: true, externalPower: true),
        adapter: adapter(connected: false)))
  }

  func testBatterylessMacFallsBackToAdapterSignal() {
    XCTAssertTrue(
      ExternalPowerResolver.isConnected(
        battery: battery(present: false, externalPower: false),
        adapter: adapter(connected: true)))
    XCTAssertFalse(
      ExternalPowerResolver.isConnected(
        battery: battery(present: false, externalPower: false),
        adapter: adapter(connected: false)))
  }

  func testUnavailableBatteryFallsBackToAdapterAndMissingInputsAreSafe() {
    XCTAssertTrue(
      ExternalPowerResolver.isConnected(
        battery: nil,
        adapter: adapter(connected: true)))
    XCTAssertFalse(ExternalPowerResolver.isConnected(battery: nil, adapter: nil))
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
