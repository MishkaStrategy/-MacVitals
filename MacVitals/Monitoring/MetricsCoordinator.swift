import Combine
import Foundation
import OSLog

@MainActor
final class MetricsCoordinator: ObservableObject {
  @Published private(set) var snapshot: SystemSnapshot = .empty
  @Published private(set) var cpuHistory: [TimedPoint] = []
  @Published private(set) var memoryHistory: [TimedPoint] = []
  @Published private(set) var isRunning = false

  private let cpuProvider = CPUProvider()
  private let memoryProvider = MemoryProvider()
  private let batteryProvider = BatteryProvider()
  private let adapterProvider = AdapterProvider()
  private let gpuProvider: GPUProviding = CapabilityGPUProvider()
  private var evaluator = ChargerSufficiencyEvaluator()
  private var cpuBuffer = RingBuffer<TimedPoint>(capacity: 450)
  private var memoryBuffer = RingBuffer<TimedPoint>(capacity: 450)
  private var samplingTask: Task<Void, Never>?

  func start() {
    guard samplingTask == nil else { return }
    isRunning = true
    samplingTask = Task { [weak self] in
      while !Task.isCancelled {
        await self?.sample()
        let nanos = UInt64(max(0.5, self?.currentInterval ?? 2) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
      }
    }
  }

  func stop() {
    samplingTask?.cancel()
    samplingTask = nil
    isRunning = false
  }

  func handleSleep() {
    stop()
    cpuProvider.resetBaseline()
    evaluator.reset()
    cpuBuffer.append(TimedPoint(value: nil, discontinuity: true))
    memoryBuffer.append(TimedPoint(value: nil, discontinuity: true))
    publishHistory()
  }

  func handleWake() {
    cpuProvider.resetBaseline()
    evaluator.reset()
    start()
  }

  private var currentInterval: TimeInterval {
    UserDefaults.standard.double(forKey: "samplingInterval").nonZero ?? 2
  }

  private func sample() async {
    let cpu = cpuProvider.sample()
    let memory = memoryProvider.sample()
    let battery = batteryProvider.sample()
    let adapter = adapterProvider.sample()
    let gpu = gpuProvider.sample()
    let batteryValue = battery.value
    let adapterValue = adapter.value
    let powerSample = PowerSample(
      timestamp: Date(),
      externalPower: batteryValue?.externalPowerConnected ?? adapterValue?.connected ?? false,
      batteryPowerWatts: batteryValue?.batteryPowerWatts,
      adapterRatedPowerWatts: adapterValue?.ratedPowerWatts,
      adapterMeasuredPowerWatts: adapterValue?.measuredPowerWatts,
      batteryPercent: batteryValue?.percentage,
      batteryTimestamp: battery.timestamp,
      adapterTimestamp: adapter.timestamp)
    let assessment = evaluator.evaluate(powerSample)
    let power = MetricValue(
      value: assessment, unit: .watts,
      availability: assessment.status == .unknown ? .temporarilyUnavailable : .available,
      quality: .derived, source: .derivedPowerModel,
      timestamp: Date(), isEstimated: assessment.estimatedSystemPowerWatts != nil,
      message: assessment.explanation)
    snapshot = SystemSnapshot(
      timestamp: Date(), cpu: cpu, memory: memory,
      battery: battery, adapter: adapter, gpu: gpu, power: power)
    cpuBuffer.append(TimedPoint(value: cpu.value?.total))
    memoryBuffer.append(TimedPoint(value: memory.value?.usedPercent))
    publishHistory()
  }

  private func publishHistory() {
    cpuHistory = cpuBuffer.values
    memoryHistory = memoryBuffer.values
  }
}

extension Double {
  fileprivate var nonZero: Double? { self > 0 ? self : nil }
}
