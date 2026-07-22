import Dispatch
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

  func sample() -> SampleResult {
    let totalStart = DispatchTime.now().uptimeNanoseconds
    let (cpu, cpuMilliseconds) = measure { cpuProvider.sample() }
    let (memory, memoryMilliseconds) = measure { memoryProvider.sample() }
    let (battery, batteryMilliseconds) = measure { batteryProvider.sample() }
    let (adapter, adapterMilliseconds) = measure { adapterProvider.sample() }
    let (gpu, gpuMilliseconds) = measure { gpuProvider.sample() }
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
    let (assessment, powerModelMilliseconds) = measure { evaluator.evaluate(powerSample) }
    let power = MetricValue(
      value: assessment,
      unit: .watts,
      availability: assessment.status == .unknown ? .temporarilyUnavailable : .available,
      quality: .derived,
      source: .derivedPowerModel,
      timestamp: now,
      isEstimated: assessment.estimatedSystemPowerWatts != nil,
      message: assessment.explanation)

    let snapshot = SystemSnapshot(
      timestamp: now,
      cpu: cpu,
      memory: memory,
      battery: battery,
      adapter: adapter,
      gpu: gpu,
      power: power)
    let totalEnd = DispatchTime.now().uptimeNanoseconds
    let timings = SamplingTimings(
      cpuMilliseconds: cpuMilliseconds,
      memoryMilliseconds: memoryMilliseconds,
      batteryMilliseconds: batteryMilliseconds,
      adapterMilliseconds: adapterMilliseconds,
      gpuMilliseconds: gpuMilliseconds,
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
      SamplingTimingMath.milliseconds(startNanoseconds: start, endNanoseconds: end))
  }
}
