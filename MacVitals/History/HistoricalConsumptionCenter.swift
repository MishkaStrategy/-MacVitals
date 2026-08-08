import AppKit
import Combine
import Foundation

@MainActor
final class HistoricalConsumptionCenter: ObservableObject {
  static let shared = HistoricalConsumptionCenter()

  @Published private(set) var revision: UInt64 = 0
  @Published private(set) var isCollecting = false
  @Published private(set) var historyStartedAt: Date?

  private let center = ProcessMetricsSamplingCenter.shared
  private let store = HistoricalConsumptionArchiveStore()
  private var samplingTask: Task<Void, Never>?
  private var lastSnapshotAt: Date?
  private var currentInterval: TimeInterval = 1
  private var generation: UInt64 = 0

  private init() {}

  func start(interval: TimeInterval, initialDelay: TimeInterval = 1) {
    currentInterval = normalizedInterval(interval)
    guard samplingTask == nil else { return }

    generation &+= 1
    let activeGeneration = generation
    let subscriberID = UUID()
    let delay = normalizedDelay(initialDelay)
    isCollecting = true

    samplingTask = Task { [weak self, center, store] in
      if delay > 0 {
        do {
          try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
          return
        }
      }
      guard let self, self.generation == activeGeneration, !Task.isCancelled else { return }

      await center.subscribe(subscriberID)
      defer {
        Task { await center.unsubscribe(subscriberID) }
      }

      if let first = await store.firstRecordedAt(),
        self.generation == activeGeneration,
        !Task.isCancelled
      {
        self.historyStartedAt = first
      }

      while !Task.isCancelled {
        guard self.generation == activeGeneration else { return }
        let descriptors = self.runningApplicationDescriptors()
        let snapshot = await center.sample(
          runningApplications: descriptors,
          minimumInterval: self.currentInterval)
        guard !Task.isCancelled, self.generation == activeGeneration else { return }

        let previous = self.lastSnapshotAt
        self.lastSnapshotAt = snapshot.timestamp
        if let previous {
          let elapsed = snapshot.timestamp.timeIntervalSince(previous)
          await store.record(snapshot: snapshot, elapsed: elapsed)
          guard !Task.isCancelled, self.generation == activeGeneration else { return }
          self.revision &+= 1
          self.historyStartedAt = await store.firstRecordedAt()
        }

        let nanoseconds = UInt64(self.currentInterval * 1_000_000_000)
        do {
          try await Task.sleep(nanoseconds: nanoseconds)
        } catch {
          return
        }
      }
    }
  }

  func restart(interval: TimeInterval) {
    let normalized = normalizedInterval(interval)
    guard normalized != currentInterval else { return }
    stop(flush: false)
    start(interval: normalized, initialDelay: 0)
  }

  func stop(flush: Bool = true) {
    stopCollection()
    if flush {
      Task { [store] in await store.flush() }
    }
  }

  func stopAndFlush() async {
    stopCollection()
    await store.flush()
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

  private func stopCollection() {
    generation &+= 1
    samplingTask?.cancel()
    samplingTask = nil
    isCollecting = false
    lastSnapshotAt = nil
  }

  private func normalizedInterval(_ interval: TimeInterval) -> TimeInterval {
    min(30, max(1, interval.isFinite ? interval : 5))
  }

  private func normalizedDelay(_ delay: TimeInterval) -> TimeInterval {
    min(10, max(0, delay.isFinite ? delay : 1))
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

  deinit {
    samplingTask?.cancel()
  }
}
