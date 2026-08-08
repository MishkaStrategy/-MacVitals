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
  private var lifetimeContinuation: AsyncStream<Void>.Continuation?
  private var lastSnapshotAt: Date?
  private var currentInterval: TimeInterval = 1
  private var generation: UInt64 = 0

  private init() {}

  func start(interval: TimeInterval, initialDelay: TimeInterval = 1) {
    start(
      interval: interval,
      initialDelay: initialDelay,
      waitingFor: nil)
  }

  func restart(interval: TimeInterval) {
    let normalized = normalizedInterval(interval)
    guard normalized != currentInterval else { return }
    let previousTask = stopCollection()
    start(
      interval: normalized,
      initialDelay: 0,
      waitingFor: previousTask)
  }

  func stop(flush: Bool = true) {
    let previousTask = stopCollection()
    if flush {
      Task { [store] in
        await previousTask?.value
        await store.flush()
      }
    }
  }

  func stopAndFlush() async {
    let previousTask = stopCollection()
    await previousTask?.value
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

  private func start(
    interval: TimeInterval,
    initialDelay: TimeInterval,
    waitingFor previousTask: Task<Void, Never>?
  ) {
    currentInterval = normalizedInterval(interval)
    guard samplingTask == nil else { return }

    generation &+= 1
    let activeGeneration = generation
    let subscriberID = UUID()
    let delay = normalizedDelay(initialDelay)
    let refreshInterval = currentInterval
    let lifetime = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    lifetimeContinuation = lifetime.continuation
    isCollecting = true

    samplingTask = Task { [weak self, center, store] in
      await previousTask?.value
      guard !Task.isCancelled else { return }

      if delay > 0 {
        do {
          try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
          return
        }
      }
      guard self?.generation == activeGeneration, !Task.isCancelled else { return }

      await center.subscribe(
        subscriberID,
        minimumInterval: refreshInterval
      ) { [weak self] snapshot in
        guard let self else { return }
        await self.consume(snapshot, generation: activeGeneration)
      }

      guard !Task.isCancelled, self?.generation == activeGeneration else {
        await center.unsubscribe(subscriberID)
        return
      }

      if let first = await store.firstRecordedAt(),
        self?.generation == activeGeneration,
        !Task.isCancelled
      {
        self?.historyStartedAt = first
      }

      for await _ in lifetime.stream {
        if Task.isCancelled { break }
      }
      await center.unsubscribe(subscriberID)
    }
  }

  private func consume(
    _ snapshot: ProcessMetricsSnapshot,
    generation activeGeneration: UInt64
  ) async {
    guard generation == activeGeneration, isCollecting else { return }

    let previous = lastSnapshotAt
    lastSnapshotAt = snapshot.timestamp
    if let previous {
      let elapsed = snapshot.timestamp.timeIntervalSince(previous)
      await store.record(snapshot: snapshot, elapsed: elapsed)
      guard generation == activeGeneration, isCollecting else { return }
      revision &+= 1
      historyStartedAt = await store.firstRecordedAt()
    }
  }

  @discardableResult
  private func stopCollection() -> Task<Void, Never>? {
    generation &+= 1
    let previousTask = samplingTask
    lifetimeContinuation?.finish()
    lifetimeContinuation = nil
    previousTask?.cancel()
    samplingTask = nil
    isCollecting = false
    lastSnapshotAt = nil
    return previousTask
  }

  private func normalizedInterval(_ interval: TimeInterval) -> TimeInterval {
    min(30, max(1, interval.isFinite ? interval : 5))
  }

  private func normalizedDelay(_ delay: TimeInterval) -> TimeInterval {
    min(10, max(0, delay.isFinite ? delay : 1))
  }

  deinit {
    lifetimeContinuation?.finish()
    samplingTask?.cancel()
  }
}