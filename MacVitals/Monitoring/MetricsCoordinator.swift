import Combine
import Foundation
import OSLog

nonisolated struct SnapshotHistoryPoints: Sendable, Equatable {
  let cpu: TimedPoint
  let memory: TimedPoint

  static func make(from snapshot: SystemSnapshot) -> Self {
    Self(
      cpu: TimedPoint(timestamp: snapshot.timestamp, value: snapshot.cpu.value?.total),
      memory: TimedPoint(timestamp: snapshot.timestamp, value: snapshot.memory.value?.usedPercent))
  }
}

@MainActor
final class MetricsCoordinator: ObservableObject {
  @Published private(set) var snapshot: SystemSnapshot = .empty
  @Published private(set) var cpuHistory: [TimedPoint] = []
  @Published private(set) var memoryHistory: [TimedPoint] = []
  @Published private(set) var samplingHealth: SamplingHealth?
  @Published private(set) var isRunning = false

  var onSnapshot: ((SystemSnapshot) -> Void)?

  private let sampler = SystemSampler()
  private var cpuBuffer = RingBuffer<TimedPoint>(capacity: 450)
  private var memoryBuffer = RingBuffer<TimedPoint>(capacity: 450)
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
    cpuBuffer.append(TimedPoint(value: nil, discontinuity: true))
    memoryBuffer.append(TimedPoint(value: nil, discontinuity: true))
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
    publishHistory()
  }

  private func publishHistory() {
    cpuHistory = cpuBuffer.values
    memoryHistory = memoryBuffer.values
  }
}
