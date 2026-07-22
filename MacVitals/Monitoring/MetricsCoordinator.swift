import Combine
import Foundation
import OSLog

@MainActor
final class MetricsCoordinator: ObservableObject {
  @Published private(set) var snapshot: SystemSnapshot = .empty
  @Published private(set) var cpuHistory: [TimedPoint] = []
  @Published private(set) var memoryHistory: [TimedPoint] = []
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
        let newSnapshot = await sampler.sample()
        guard !Task.isCancelled else { break }
        self?.consume(newSnapshot)

        let nanos = UInt64(max(0.5, self?.currentInterval ?? 2) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
      }
    }
  }

  private func consume(_ newSnapshot: SystemSnapshot) {
    snapshot = newSnapshot
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
