import Dispatch
import Foundation

nonisolated enum BatterylessPowerAssessment {
  static func make(battery: BatteryStats?) -> PowerAssessment? {
    guard battery?.present == false else { return nil }
    return PowerAssessment(
      status: .powerAdapterOnly,
      confidence: 1,
      batteryPowerWatts: nil,
      estimatedSystemPowerWatts: nil,
      powerBalanceWatts: nil,
      explanation: L10n.string("No battery"))
  }
}

nonisolated enum SystemPowerAssessmentResolver {
  static func resolve(
    assessment: PowerAssessment,
    battery: BatteryStats?,
    externalPowerState: ExternalPowerState,
    directSystemPowerWatts: Double? = nil
  ) -> PowerAssessment {
    if let directSystemPowerWatts,
      directSystemPowerWatts.isFinite,
      (0.01...500).contains(directSystemPowerWatts)
    {
      return PowerAssessment(
        status: assessment.status,
        confidence: 1,
        batteryPowerWatts: assessment.batteryPowerWatts ?? battery?.batteryPowerWatts,
        estimatedSystemPowerWatts: directSystemPowerWatts,
        powerBalanceWatts: assessment.powerBalanceWatts,
        explanation: L10n.string("Direct system power sensor"),
        adapterInputPowerWatts: assessment.adapterInputPowerWatts)
    }

    guard assessment.estimatedSystemPowerWatts == nil,
      externalPowerState == .disconnected,
      battery?.state == .discharging,
      let batteryPower = battery?.batteryPowerWatts,
      batteryPower.isFinite,
      abs(batteryPower) > 0.01
    else { return assessment }

    return PowerAssessment(
      status: assessment.status,
      confidence: assessment.confidence,
      batteryPowerWatts: assessment.batteryPowerWatts ?? batteryPower,
      estimatedSystemPowerWatts: abs(batteryPower),
      powerBalanceWatts: assessment.powerBalanceWatts,
      explanation: assessment.explanation,
      adapterInputPowerWatts: assessment.adapterInputPowerWatts)
  }
}

actor SystemSampler {
  private let cpuProvider = CPUProvider()
  private let memoryProvider = MemoryProvider()
  private let batteryProvider = BatteryProvider()
  private let adapterProvider = AdapterProvider()
  private let powerTelemetryProvider = SystemPowerTelemetryProvider()
  private let gpuProvider: any GPUProviding = CapabilityGPUProvider()
  private let temperatureProvider = TemperatureProvider()
  private let fanProvider = FanProvider()
  private var evaluator = ChargerSufficiencyEvaluator()
  private let providerTimingDiagnosticsURL: URL? = {
    guard let path = ProcessInfo.processInfo.environment["MACVITALS_PROVIDER_TIMINGS_PATH"],
      !path.isEmpty
    else { return nil }
    return URL(fileURLWithPath: path)
  }()

  func resetForDiscontinuity() {
    cpuProvider.resetBaseline()
    temperatureProvider.resetConnection()
    fanProvider.resetConnection()
    evaluator.reset()
  }

  func sample() -> SampleResult {
    let totalStart = DispatchTime.now().uptimeNanoseconds
    let (cpu, cpuMilliseconds) = measure { cpuProvider.sample() }
    let (memory, memoryMilliseconds) = measure { memoryProvider.sample() }
    let (battery, batteryMilliseconds) = measure { batteryProvider.sample() }
    let (adapter, adapterMilliseconds) = measure { adapterProvider.sample() }
    let (telemetry, powerTelemetryMilliseconds) = measure { powerTelemetryProvider.sample() }
    let (gpu, gpuMilliseconds) = measure { gpuProvider.sample() }
    let now = Date()
    let (temperature, temperatureMilliseconds) = measure {
      temperatureProvider.sample(
        batteryTemperatureCelsius: battery.value?.temperatureCelsius,
        now: now)
    }
    let (fans, fanMilliseconds) = measure { fanProvider.sample() }
    let batteryValue = battery.value
    let adapterValue = adapter.value
    let externalPowerState = ExternalPowerResolver.resolve(
      battery: batteryValue,
      batteryAvailability: battery.availability,
      adapter: adapterValue,
      adapterAvailability: adapter.availability)

    let adapterInputPower = telemetry?.systemInputWatts ?? adapterValue?.measuredPowerWatts
    let powerSample = PowerSample(
      timestamp: now,
      externalPower: externalPowerState == .connected,
      batteryPowerWatts: batteryValue?.batteryPowerWatts,
      adapterRatedPowerWatts: adapterValue?.ratedPowerWatts,
      adapterMeasuredPowerWatts: adapterInputPower,
      batteryPercent: batteryValue?.percentage,
      batteryTimestamp: battery.timestamp,
      adapterTimestamp: adapter.timestamp)
    let (rawAssessment, powerModelMilliseconds) = measure {
      if let directAssessment = BatterylessPowerAssessment.make(battery: batteryValue) {
        evaluator.reset()
        return directAssessment
      }
      if let unknownAssessment = UnknownExternalPowerAssessment.make(for: externalPowerState) {
        evaluator.reset()
        return unknownAssessment
      }
      return evaluator.evaluate(powerSample)
    }
    let resolvedAssessment = SystemPowerAssessmentResolver.resolve(
      assessment: rawAssessment,
      battery: batteryValue,
      externalPowerState: externalPowerState,
      directSystemPowerWatts: telemetry?.systemLoadWatts)
    let assessment = PowerAssessment(
      status: resolvedAssessment.status,
      confidence: resolvedAssessment.confidence,
      batteryPowerWatts: resolvedAssessment.batteryPowerWatts ?? batteryValue?.batteryPowerWatts,
      estimatedSystemPowerWatts: resolvedAssessment.estimatedSystemPowerWatts,
      powerBalanceWatts: resolvedAssessment.powerBalanceWatts,
      explanation: resolvedAssessment.explanation,
      adapterInputPowerWatts: adapterInputPower)
    let hasDirectSystemPower = telemetry?.systemLoadWatts != nil
    let power = MetricValue(
      value: assessment,
      unit: .watts,
      availability: assessment.estimatedSystemPowerWatts == nil
        ? .temporarilyUnavailable : .available,
      quality: hasDirectSystemPower ? .direct : .derived,
      source: hasDirectSystemPower ? .iokitRegistry : .derivedPowerModel,
      timestamp: now,
      isEstimated: !hasDirectSystemPower && assessment.estimatedSystemPowerWatts != nil,
      message: assessment.explanation)

    let snapshot = SystemSnapshot(
      timestamp: now,
      cpu: cpu,
      memory: memory,
      battery: battery,
      adapter: adapter,
      gpu: gpu,
      temperature: temperature,
      fans: fans,
      power: power)
    let totalEnd = DispatchTime.now().uptimeNanoseconds
    let totalMilliseconds = SamplingTimingMath.milliseconds(
      startNanoseconds: totalStart,
      endNanoseconds: totalEnd)
    let timings = SamplingTimings(
      cpuMilliseconds: cpuMilliseconds,
      memoryMilliseconds: memoryMilliseconds,
      batteryMilliseconds: batteryMilliseconds,
      adapterMilliseconds: adapterMilliseconds,
      gpuMilliseconds: gpuMilliseconds,
      fanMilliseconds: fanMilliseconds,
      powerModelMilliseconds: powerModelMilliseconds,
      totalMilliseconds: totalMilliseconds)

    recordProviderTimings(
      timestamp: now,
      cpuMilliseconds: cpuMilliseconds,
      memoryMilliseconds: memoryMilliseconds,
      batteryMilliseconds: batteryMilliseconds,
      adapterMilliseconds: adapterMilliseconds,
      powerTelemetryMilliseconds: powerTelemetryMilliseconds,
      gpuMilliseconds: gpuMilliseconds,
      temperatureMilliseconds: temperatureMilliseconds,
      fanMilliseconds: fanMilliseconds,
      powerModelMilliseconds: powerModelMilliseconds,
      totalMilliseconds: totalMilliseconds)

    return SampleResult(snapshot: snapshot, timings: timings)
  }

  private func measure<Value>(_ operation: () -> Value) -> (Value, Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = operation()
    let end = DispatchTime.now().uptimeNanoseconds
    return (
      value,
      SamplingTimingMath.milliseconds(startNanoseconds: start, endNanoseconds: end)
    )
  }

  private func recordProviderTimings(
    timestamp: Date,
    cpuMilliseconds: Double,
    memoryMilliseconds: Double,
    batteryMilliseconds: Double,
    adapterMilliseconds: Double,
    powerTelemetryMilliseconds: Double,
    gpuMilliseconds: Double,
    temperatureMilliseconds: Double,
    fanMilliseconds: Double,
    powerModelMilliseconds: Double,
    totalMilliseconds: Double
  ) {
    guard let providerTimingDiagnosticsURL else { return }

    let record: [String: Any] = [
      "timestamp": timestamp.timeIntervalSince1970,
      "cpu_ms": cpuMilliseconds,
      "memory_ms": memoryMilliseconds,
      "battery_ms": batteryMilliseconds,
      "adapter_ms": adapterMilliseconds,
      "power_telemetry_ms": powerTelemetryMilliseconds,
      "gpu_ms": gpuMilliseconds,
      "temperature_ms": temperatureMilliseconds,
      "fan_ms": fanMilliseconds,
      "power_model_ms": powerModelMilliseconds,
      "total_ms": totalMilliseconds,
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    else { return }

    let directory = providerTimingDiagnosticsURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: providerTimingDiagnosticsURL.path) {
      FileManager.default.createFile(atPath: providerTimingDiagnosticsURL.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: providerTimingDiagnosticsURL) else { return }
    defer { try? handle.close() }
    do {
      try handle.seekToEnd()
      try handle.write(contentsOf: json)
      try handle.write(contentsOf: Data([0x0A]))
    } catch {
      return
    }
  }
}
