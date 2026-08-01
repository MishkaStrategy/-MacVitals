import AppKit
import Combine
import Foundation

@MainActor
final class HistoricalConsumptionCenter: ObservableObject {
  static let shared = HistoricalConsumptionCenter()

  @Published private(set) var revision: UInt64 = 0
  @Published private(set) var isCollecting = false
  @Published private(set) var historyStartedAt: Date?

  private let provider = ProcessMetricsProvider()
  private let store = HistoricalConsumptionArchiveStore()
  private var samplingTask: Task<Void, Never>?
  private var lastSnapshotAt: Date?
  private var currentInterval: TimeInterval = 1

  private init() {}

  func start(interval: TimeInterval) {
    currentInterval = normalizedInterval(interval)
    guard samplingTask == nil else { return }
    isCollecting = true
    samplingTask = Task { [weak self, provider, store] in
      await provider.reset()
      if let first = await store.firstRecordedAt() {
        self?.historyStartedAt = first
      }
      while !Task.isCancelled {
        guard let self else { return }
        let descriptors = runningApplicationDescriptors()
        let snapshot = await provider.sample(runningApplications: descriptors)
        guard !Task.isCancelled else { return }
        if let previous = lastSnapshotAt {
          let elapsed = snapshot.timestamp.timeIntervalSince(previous)
          await store.record(snapshot: snapshot, elapsed: elapsed)
          revision &+= 1
          historyStartedAt = await store.firstRecordedAt()
        }
        lastSnapshotAt = snapshot.timestamp
        try? await Task.sleep(
          nanoseconds: UInt64(currentInterval * 1_000_000_000))
      }
    }
  }

  func restart(interval: TimeInterval) {
    let normalized = normalizedInterval(interval)
    guard normalized != currentInterval else { return }
    stop(flush: false)
    start(interval: normalized)
  }

  func stop(flush: Bool = true) {
    samplingTask?.cancel()
    samplingTask = nil
    isCollecting = false
    lastSnapshotAt = nil
    if flush {
      Task { [store] in await store.flush() }
    }
  }

  func leaders(
    metric: HistoricalConsumptionMetric,
    range: HistoricalConsumptionRange
  ) async -> [HistoricalConsumptionLeader] {
    await store.leaders(metric: metric, range: range)
  }

  func coverageDuration(range: HistoricalConsumptionRange) async -> TimeInterval {
    await store.coverageDuration(range: range)
  }

  private func normalizedInterval(_ interval: TimeInterval) -> TimeInterval {
    min(30, max(1, interval.isFinite ? interval : 5))
  }

  private func runningApplicationDescriptors() -> [RunningApplicationDescriptor] {
    NSWorkspace.shared.runningApplications.compactMap { application in
      guard !application.isTerminated, application.processIdentifier > 0 else { return nil }
      let name = application.localizedName
        ?? application.bundleIdentifier
        ?? L10n.string("Unknown process")
      return RunningApplicationDescriptor(
        pid: application.processIdentifier,
        name: name,
        bundleIdentifier: application.bundleIdentifier)
    }
  }
}
