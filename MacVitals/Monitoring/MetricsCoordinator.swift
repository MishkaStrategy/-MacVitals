import Combine
import Foundation
import OSLog

nonisolated struct SnapshotHistoryPoints: Sendable, Equatable {
  let cpu: TimedPoint
  let memory: TimedPoint
  let gpu: TimedPoint
  let battery: TimedPoint
  let systemPower: TimedPoint

  static func make(from snapshot: SystemSnapshot) -> Self {
    Self(
      cpu: TimedPoint(timestamp: snapshot.timestamp, value: snapshot.cpu.value?.total),
      memory: TimedPoint(timestamp: snapshot.timestamp, value: snapshot.memory.value?.usedPercent),
      gpu: TimedPoint(
        timestamp: snapshot.timestamp,
        value: snapshot.gpu.value?.systemUtilizationPercent),
      battery: TimedPoint(timestamp: snapshot.timestamp, value: snapshot.battery.value?.percentage),
      systemPower: TimedPoint(
        timestamp: snapshot.timestamp,
        value: snapshot.power.value?.estimatedSystemPowerWatts))
  }
}

@MainActor
final class MetricsCoordinator: ObservableObject {
  @Published private(set) var snapshot: SystemSnapshot = .empty
  @Published private(set) var cpuHistory: [TimedPoint] = []
  @Published private(set) var memoryHistory: [TimedPoint] = []
  @Published private(set) var gpuHistory: [TimedPoint] = []
  @Published private(set) var batteryHistory: [TimedPoint] = []
  @Published private(set) var systemPowerHistory: [TimedPoint] = []
  @Published private(set) var fanHistory: [Int: [TimedPoint]] = [:]
  @Published private(set) var samplingHealth: SamplingHealth?
  @Published private(set) var isRunning = false

  var onSnapshot: ((SystemSnapshot) -> Void)?

  private let sampler = SystemSampler()
  private var cpuBuffer = RingBuffer<TimedPoint>(capacity: 720)
  private var memoryBuffer = RingBuffer<TimedPoint>(capacity: 720)
  private var gpuBuffer = RingBuffer<TimedPoint>(capacity: 720)
  private var batteryBuffer = RingBuffer<TimedPoint>(capacity: 720)
  private var systemPowerBuffer = RingBuffer<TimedPoint>(capacity: 720)
  private var fanBuffers: [Int: RingBuffer<TimedPoint>] = [:]
  private var samplingTask: Task<Void, Never>?

  func start() {
    start(resetBeforeSampling: false)
  }

  func stop() {
    samplingTask?.cancel()
    samplingTask = nil
    isRunning = false
  }

  func handleSleep() {
    stop()
    appendDiscontinuity()
    publishHistory()
  }

  func handleWake() {
    start(resetBeforeSampling: true)
  }

  private var currentInterval: TimeInterval {
    SamplingIntervalPolicy.normalized(
      UserDefaults.standard.double(forKey: "samplingInterval"))
  }

  private func start(resetBeforeSampling: Bool) {
    guard samplingTask == nil else { return }
    isRunning = true
    let sampler = self.sampler
    samplingTask = Task { [weak self, sampler] in
      if resetBeforeSampling {
        await sampler.resetForDiscontinuity()
      }

      while !Task.isCancelled {
        let result = await sampler.sample()
        guard !Task.isCancelled else { break }

        let interval = self?.currentInterval ?? SamplingIntervalPolicy.defaultValue
        self?.consume(result, configuredInterval: interval)

        let nanos = SamplingIntervalPolicy.sleepNanoseconds(
          intervalSeconds: interval,
          elapsedMilliseconds: result.timings.totalMilliseconds)
        if nanos > 0 {
          try? await Task.sleep(nanoseconds: nanos)
        } else {
          await Task.yield()
        }
      }
    }
  }

  private func consume(_ result: SampleResult, configuredInterval: TimeInterval) {
    let newSnapshot = result.snapshot
    snapshot = newSnapshot
    samplingHealth = SamplingHealth(
      timings: result.timings,
      configuredIntervalSeconds: configuredInterval)
    onSnapshot?(newSnapshot)

    let historyPoints = SnapshotHistoryPoints.make(from: newSnapshot)
    cpuBuffer.append(historyPoints.cpu)
    memoryBuffer.append(historyPoints.memory)
    gpuBuffer.append(historyPoints.gpu)
    batteryBuffer.append(historyPoints.battery)
    systemPowerBuffer.append(historyPoints.systemPower)
    appendFanHistory(from: newSnapshot)
    publishHistory()
  }

  private func appendFanHistory(from snapshot: SystemSnapshot) {
    let fans = snapshot.fans.value?.fans ?? []
    let observedIndexes = Set(fans.map(\.index))

    for fan in fans {
      var buffer = fanBuffers[fan.index] ?? RingBuffer<TimedPoint>(capacity: 720)
      buffer.append(TimedPoint(timestamp: snapshot.timestamp, value: fan.currentRPM))
      fanBuffers[fan.index] = buffer
    }

    for index in Array(fanBuffers.keys) where !observedIndexes.contains(index) {
      guard var buffer = fanBuffers[index] else { continue }
      buffer.append(TimedPoint(timestamp: snapshot.timestamp, value: nil))
      fanBuffers[index] = buffer
    }
  }

  private func appendDiscontinuity() {
    let point = TimedPoint(value: nil, discontinuity: true)
    cpuBuffer.append(point)
    memoryBuffer.append(point)
    gpuBuffer.append(point)
    batteryBuffer.append(point)
    systemPowerBuffer.append(point)

    for index in Array(fanBuffers.keys) {
      guard var buffer = fanBuffers[index] else { continue }
      buffer.append(TimedPoint(value: nil, discontinuity: true))
      fanBuffers[index] = buffer
    }
  }

  private func publishHistory() {
    cpuHistory = cpuBuffer.values
    memoryHistory = memoryBuffer.values
    gpuHistory = gpuBuffer.values
    batteryHistory = batteryBuffer.values
    systemPowerHistory = systemPowerBuffer.values
    fanHistory = fanBuffers.mapValues(\.values)
  }
}
