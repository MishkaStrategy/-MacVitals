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
        explanation: L10n.string("Direct system power telemetry"))
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
      explanation: assessment.explanation)
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
    let telemetry = powerTelemetryProvider.sample()
    let (gpu, gpuMilliseconds) = measure { gpuProvider.sample() }
    let temperature = temperatureProvider.sample(
      batteryTemperatureCelsius: battery.value?.temperatureCelsius)
    let (fans, fanMilliseconds) = measure { fanProvider.sample() }
    let batteryValue = battery.value
    let adapterValue = adapter.value
    let now = Date()
    let externalPowerState = ExternalPowerResolver.resolve(
      battery: batteryValue,
      batteryAvailability: battery.availability,
      adapter: adapterValue,
      adapterAvailability: adapter.availability)

    let powerSample = PowerSample(
      timestamp: now,
      externalPower: externalPowerState == .connected,
      batteryPowerWatts: batteryValue?.batteryPowerWatts,
      adapterRatedPowerWatts: adapterValue?.ratedPowerWatts,
      adapterMeasuredPowerWatts: telemetry?.systemInputWatts ?? adapterValue?.measuredPowerWatts,
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
    let assessment = SystemPowerAssessmentResolver.resolve(
      assessment: rawAssessment,
      battery: batteryValue,
      externalPowerState: externalPowerState,
      directSystemPowerWatts: telemetry?.systemLoadWatts)
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
    let timings = SamplingTimings(
      cpuMilliseconds: cpuMilliseconds,
      memoryMilliseconds: memoryMilliseconds,
      batteryMilliseconds: batteryMilliseconds,
      adapterMilliseconds: adapterMilliseconds,
      gpuMilliseconds: gpuMilliseconds,
      fanMilliseconds: fanMilliseconds,
      powerModelMilliseconds: powerModelMilliseconds,
      totalMilliseconds: SamplingTimingMath.milliseconds(
        startNanoseconds: totalStart,
        endNanoseconds: totalEnd))

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
}
