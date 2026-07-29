import XCTest
@testable import MacVitals

final class MenuBarRendererTests: XCTestCase {
  func testEmptyMetricsUseCompactFallback() {
    XCTAssertEqual(MenuBarRenderer.render(snapshot: .empty, metrics: []), "◉")
  }

  func testUnavailableMetricsRemainVisible() {
    XCTAssertEqual(
      MenuBarRenderer.render(snapshot: .empty, metrics: [.cpu, .gpu, .memory]),
      "CPU —  ·  GPU —  ·  RAM —")
    XCTAssertEqual(
      MenuBarRenderer.render(
        snapshot: .empty,
        metrics: [.temperature, .battery, .fans, .systemPower, .adapterPower, .powerStatus]),
      "🌡 —  ·  🔋 —  ·  🌀 —  ·  ⚡ —  ·  🔌 —  ·  ?")
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

  func testTemperatureMetricRendersProcessorAndBattery() {
    XCTAssertEqual(
      MenuBarRenderer.render(
        snapshot: snapshot(processorTemperature: 63.6, batteryTemperature: 32.4),
        metrics: [.temperature]),
      "🌡 64°/32°")
    XCTAssertEqual(
      MenuBarRenderer.render(
        snapshot: snapshot(processorTemperature: nil, batteryTemperature: 32.4),
        metrics: [.temperature]),
      "🌡 🔋32°")
  }

  func testBatteryMetricStaysCompactAndTemperatureHasOwnMetric() {
    XCTAssertEqual(
      MenuBarRenderer.render(
        snapshot: snapshot(batteryPercentage: 49.6, batteryTemperature: 32.4),
        metrics: [.battery, .temperature]),
      "🔋 50%  ·  🌡 🔋32°")
  }

  func testPowerMetricsPreferLiveSystemAndAdapterMeasurements() {
    XCTAssertEqual(
      MenuBarRenderer.render(
        snapshot: snapshot(systemPower: 18.25, adapterInputPower: 27.75),
        metrics: [.systemPower, .adapterPower]),
      "⚡ 18.2 W  ·  🔌 27.8 W")
  }

  func testAdapterMetricFallsBackToRatedCapability() {
    XCTAssertEqual(
      MenuBarRenderer.render(
        snapshot: snapshot(adapterInputPower: nil, adapterRatedPower: 67),
        metrics: [.adapterPower]),
      "🔌 ≤67 W")
  }

  func testInvalidNumericMetricsUseUnavailablePlaceholders() {
    XCTAssertEqual(
      MenuBarRenderer.render(
        snapshot: snapshot(
          batteryPercentage: .nan,
          processorTemperature: .infinity,
          batteryTemperature: .nan,
          systemPower: -.infinity,
          adapterInputPower: .nan),
        metrics: [.temperature, .battery, .systemPower, .adapterPower]),
      "🌡 —  ·  🔋 —  ·  ⚡ —  ·  🔌 —")
  }

  func testFanMetricRendersOneAndTwoCurrentSpeeds() {
    XCTAssertEqual(
      MenuBarRenderer.render(
        snapshot: snapshot(fans: [fan(index: 0, current: 2_101)]),
        metrics: [.fans]),
      "🌀 2101 RPM")
    XCTAssertEqual(
      MenuBarRenderer.render(
        snapshot: snapshot(
          fans: [fan(index: 0, current: 1_900), fan(index: 1, current: 2_100)]),
        metrics: [.fans]),
      "🌀 1900/2100 RPM")
  }

  func testFanMetricNeverPrintsInvalidNumbers() {
    XCTAssertEqual(
      MenuBarRenderer.render(
        snapshot: snapshot(fans: [fan(index: 0, current: .nan)]),
        metrics: [.fans]),
      "🌀 —")
  }

  private func snapshot(
    batteryPercentage: Double? = nil,
    processorTemperature: Double? = nil,
    batteryTemperature: Double? = nil,
    fans: [FanReading]? = nil,
    systemPower: Double? = nil,
    adapterInputPower: Double? = nil,
    adapterRatedPower: Double? = nil
  ) -> SystemSnapshot {
    let now = Date(timeIntervalSince1970: 100)
    let battery = BatteryStats(
      present: true,
      percentage: batteryPercentage,
      state: .unknown,
      externalPowerConnected: adapterInputPower != nil,
      timeRemainingMinutes: nil,
      timeToFullMinutes: nil,
      cycleCount: nil,
      condition: nil,
      currentCapacityMah: nil,
      maxCapacityMah: nil,
      designCapacityMah: nil,
      healthPercent: nil,
      temperatureCelsius: batteryTemperature,
      voltageVolts: nil,
      currentAmperes: nil,
      batteryPowerWatts: nil)

    let temperatureSensors: [TemperatureReading] = [
      processorTemperature.map {
        TemperatureReading(
          id: "smc.TCMz",
          key: "TCMz",
          name: "CPU hotspot",
          category: .processor,
          celsius: $0,
          source: .appleSMC,
          isPrimary: true)
      },
      batteryTemperature.map {
        TemperatureReading(
          id: "battery.iokit",
          name: "Battery temperature",
          category: .battery,
          celsius: $0,
          source: .iokitRegistry,
          isPrimary: true)
      },
    ].compactMap { $0 }

    return SystemSnapshot(
      timestamp: now,
      cpu: .unavailable(unit: .percent),
      memory: .unavailable(unit: .bytes),
      battery: MetricValue(
        value: battery,
        unit: .percent,
        availability: .available,
        quality: .direct,
        source: .iokitPowerSources,
        timestamp: now,
        isEstimated: false,
        message: nil),
      adapter: MetricValue(
        value: AdapterStats(
          connected: adapterInputPower != nil || adapterRatedPower != nil,
          manufacturer: nil,
          model: nil,
          transport: nil,
          ratedPowerWatts: adapterRatedPower,
          voltageVolts: nil,
          currentAmperes: nil,
          measuredPowerWatts: adapterInputPower),
        unit: .watts,
        availability: .available,
        quality: .direct,
        source: .iokitPowerSources,
        timestamp: now,
        isEstimated: false,
        message: nil),
      gpu: .unavailable(unit: .percent),
      temperature: MetricValue(
        value: TemperatureStats(
          processorCelsius: processorTemperature,
          batteryCelsius: batteryTemperature,
          maximumCelsius: temperatureSensors.map(\.celsius).max(),
          processorSensorKey: processorTemperature == nil ? nil : "TCMz",
          sensors: temperatureSensors),
        unit: .celsius,
        availability: temperatureSensors.isEmpty ? .temporarilyUnavailable : .available,
        quality: .direct,
        source: temperatureSensors.isEmpty ? .unavailable : .appleSMC,
        timestamp: now,
        isEstimated: false,
        message: nil),
      fans: fans.map {
        MetricValue(
          value: FanStats(fans: $0),
          unit: .rpm,
          availability: .available,
          quality: .experimental,
          source: .appleSMC,
          timestamp: now,
          isEstimated: false,
          message: nil)
      } ?? .unavailable(unit: .rpm, availability: .temporarilyUnavailable),
      power: MetricValue(
        value: PowerAssessment(
          status: .unknown,
          confidence: 1,
          batteryPowerWatts: nil,
          estimatedSystemPowerWatts: systemPower,
          powerBalanceWatts: nil,
          explanation: "Test",
          adapterInputPowerWatts: adapterInputPower),
        unit: .watts,
        availability: systemPower == nil && adapterInputPower == nil ? .temporarilyUnavailable : .available,
        quality: .direct,
        source: .iokitRegistry,
        timestamp: now,
        isEstimated: false,
        message: nil))
  }

  private func fan(index: Int, current: Double?) -> FanReading {
    FanReading(
      index: index,
      currentRPM: current,
      targetRPM: nil,
      minimumRPM: 1_200,
      maximumRPM: 6_000,
      mode: .automatic)
  }
}
