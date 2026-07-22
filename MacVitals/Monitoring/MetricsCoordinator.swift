import Combine
import Foundation
import OSLog

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
    UserDefaults.standard.double(forKey: "samplingInterval").nonZero ?? 2
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

        let interval = self?.currentInterval ?? 2
        self?.consume(result, configuredInterval: interval)

        let delay = SamplingTimingMath.remainingDelaySeconds(
          intervalSeconds: interval,
          elapsedMilliseconds: result.timings.totalMilliseconds)
        let nanos = UInt64(delay * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
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
    cpuBuffer.append(TimedPoint(value: newSnapshot.cpu.value?.total))
    memoryBuffer.append(TimedPoint(value: newSnapshot.memory.value?.usedPercent))
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
