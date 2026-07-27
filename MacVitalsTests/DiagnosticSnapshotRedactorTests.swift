import XCTest
@testable import MacVitals

final class DiagnosticSnapshotRedactorTests: XCTestCase {
  func testRedactedSnapshotEncodesWithoutNonFiniteValues() throws {
    let invalidDate = Date(timeIntervalSinceReferenceDate: .nan)
    let snapshot = SystemSnapshot(
      timestamp: invalidDate,
      cpu: MetricValue(
        value: CPUStats(
          total: .nan,
          user: .infinity,
          system: 0,
          idle: 0,
          logicalProcessors: 1,
          activeProcessors: 1),
        unit: .percent,
        availability: .available,
        quality: .direct,
        source: .machHostStatistics,
        timestamp: invalidDate,
        isEstimated: false,
        message: nil),
      memory: MetricValue(
        value: MemoryStats(
          physicalBytes: 100,
          usedBytes: 50,
          freeBytes: 50,
          availableBytes: 50,
          activeBytes: 0,
          inactiveBytes: 0,
          wiredBytes: 0,
          compressedBytes: 0,
          purgeableBytes: 0,
          speculativeBytes: 0,
          swapTotalBytes: nil,
          swapUsedBytes: nil,
          swapFreeBytes: nil,
          pressureLevel: .normal,
          usedPercent: .infinity),
        unit: .bytes,
        availability: .available,
        quality: .derived,
        source: .machHostStatistics,
        timestamp: invalidDate,
        isEstimated: false,
        message: nil),
      battery: MetricValue(
        value: BatteryStats(
          present: true,
          percentage: .nan,
          state: .unknown,
          externalPowerConnected: false,
          timeRemainingMinutes: -1,
          timeToFullMinutes: -1,
          cycleCount: -1,
          condition: nil,
          currentCapacityMah: .infinity,
          maxCapacityMah: .nan,
          designCapacityMah: -1,
          healthPercent: .infinity,
          temperatureCelsius: .nan,
          voltageVolts: -.infinity,
          currentAmperes: .infinity,
          batteryPowerWatts: .nan),
        unit: .percent,
        availability: .available,
        quality: .experimental,
        source: .iokitRegistry,
        timestamp: invalidDate,
        isEstimated: false,
        message: nil),
      adapter: MetricValue(
        value: AdapterStats(
          connected: true,
          manufacturer: "Test",
          model: "Adapter",
          transport: nil,
          ratedPowerWatts: .infinity,
          voltageVolts: .nan,
          currentAmperes: -.infinity,
          measuredPowerWatts: -1),
        unit: .watts,
        availability: .available,
        quality: .direct,
        source: .iokitPowerSources,
        timestamp: invalidDate,
        isEstimated: false,
        message: nil),
      gpu: MetricValue(
        value: GPUStats(
          name: "Test GPU",
          metalAvailable: true,
          registryID: 123_456,
          hasUnifiedMemory: true,
          isLowPower: true,
          isRemovable: false,
          recommendedWorkingSetBytes: 1_024,
          systemUtilizationPercent: .nan,
          utilizationAvailability: .available),
        unit: .percent,
        availability: .available,
        quality: .direct,
        source: .metal,
        timestamp: invalidDate,
        isEstimated: false,
        message: nil),
      fans: MetricValue(
        value: FanStats(fans: [
          FanReading(
            index: 0,
            currentRPM: .nan,
            targetRPM: .infinity,
            minimumRPM: 6_000,
            maximumRPM: 1_200,
            mode: .manual)
        ]),
        unit: .rpm,
        availability: .available,
        quality: .experimental,
        source: .appleSMC,
        timestamp: invalidDate,
        isEstimated: false,
        message: nil),
      power: MetricValue(
        value: PowerAssessment(
          status: .unknown,
          confidence: .nan,
          batteryPowerWatts: .infinity,
          estimatedSystemPowerWatts: -.infinity,
          powerBalanceWatts: .nan,
          explanation: "Invalid input"),
        unit: .watts,
        availability: .available,
        quality: .derived,
        source: .derivedPowerModel,
        timestamp: invalidDate,
        isEstimated: false,
        message: nil))

    let redacted = DiagnosticSnapshotRedactor.redact(snapshot)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(redacted)
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))

    XCTAssertNil(redacted.cpu.value)
    XCTAssertEqual(redacted.cpu.availability, .providerError)
    XCTAssertNil(redacted.memory.value)
    XCTAssertEqual(redacted.memory.availability, .providerError)
    XCTAssertNil(redacted.battery.value?.percentage)
    XCTAssertNil(redacted.battery.value?.batteryPowerWatts)
    XCTAssertNil(redacted.adapter.value?.ratedPowerWatts)
    XCTAssertNil(redacted.gpu.value?.registryID)
    XCTAssertNil(redacted.gpu.value?.systemUtilizationPercent)
    XCTAssertNil(redacted.fans.value)
    XCTAssertEqual(redacted.fans.availability, .providerError)
    XCTAssertNil(redacted.power.value)
    XCTAssertEqual(redacted.power.availability, .providerError)
    XCTAssertFalse(json.contains("NaN"))
    XCTAssertFalse(json.contains("Infinity"))
    XCTAssertFalse(json.contains("123456"))
  }

  func testValidFanTelemetryIsPreservedWithinBounds() throws {
    let now = Date(timeIntervalSince1970: 100)
    let metric = MetricValue(
      value: FanStats(fans: [
        FanReading(
          index: 0,
          currentRPM: 2_100,
          targetRPM: 2_400,
          minimumRPM: 1_200,
          maximumRPM: 6_000,
          mode: .automatic),
        FanReading(
          index: 1,
          currentRPM: 2_200,
          targetRPM: 2_500,
          minimumRPM: 1_300,
          maximumRPM: 6_100,
          mode: .manual),
      ]),
      unit: MetricUnit.rpm,
      availability: MetricAvailability.available,
      quality: MeasurementQuality.experimental,
      source: MetricSource.appleSMC,
      timestamp: now,
      isEstimated: false,
      message: nil)
    let redacted = DiagnosticSnapshotRedactor.redact(
      SystemSnapshot(
        timestamp: now,
        cpu: .unavailable(unit: .percent),
        memory: .unavailable(unit: .bytes),
        battery: .unavailable(unit: .percent),
        adapter: .unavailable(unit: .watts),
        gpu: .unavailable(unit: .percent),
        fans: metric,
        power: .unavailable(unit: .watts)))

    let fans = try XCTUnwrap(redacted.fans.value?.fans)
    XCTAssertEqual(fans.count, 2)
    XCTAssertEqual(fans[0].currentRPM, 2_100)
    XCTAssertEqual(fans[1].mode, .manual)
  }
}
