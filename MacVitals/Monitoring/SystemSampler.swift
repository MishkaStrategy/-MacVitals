import Foundation

actor SystemSampler {
  private let cpuProvider = CPUProvider()
  private let memoryProvider = MemoryProvider()
  private let batteryProvider = BatteryProvider()
  private let adapterProvider = AdapterProvider()
  private let gpuProvider: any GPUProviding = CapabilityGPUProvider()
  private var evaluator = ChargerSufficiencyEvaluator()

  func resetForDiscontinuity() {
    cpuProvider.resetBaseline()
    evaluator.reset()
  }

  func sample() -> SystemSnapshot {
    let cpu = cpuProvider.sample()
    let memory = memoryProvider.sample()
    let battery = batteryProvider.sample()
    let adapter = adapterProvider.sample()
    let gpu = gpuProvider.sample()
    let batteryValue = battery.value
    let adapterValue = adapter.value
    let now = Date()

    let powerSample = PowerSample(
      timestamp: now,
      externalPower: batteryValue?.externalPowerConnected ?? adapterValue?.connected ?? false,
      batteryPowerWatts: batteryValue?.batteryPowerWatts,
      adapterRatedPowerWatts: adapterValue?.ratedPowerWatts,
      adapterMeasuredPowerWatts: adapterValue?.measuredPowerWatts,
      batteryPercent: batteryValue?.percentage,
      batteryTimestamp: battery.timestamp,
      adapterTimestamp: adapter.timestamp)
    let assessment = evaluator.evaluate(powerSample)
    let power = MetricValue(
      value: assessment,
      unit: .watts,
      availability: assessment.status == .unknown ? .temporarilyUnavailable : .available,
      quality: .derived,
      source: .derivedPowerModel,
      timestamp: now,
      isEstimated: assessment.estimatedSystemPowerWatts != nil,
      message: assessment.explanation)

    return SystemSnapshot(
      timestamp: now,
      cpu: cpu,
      memory: memory,
      battery: battery,
      adapter: adapter,
      gpu: gpu,
      power: power)
  }
}
