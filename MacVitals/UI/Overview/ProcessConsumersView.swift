import AppKit
import Combine
import SwiftUI

actor ProcessMetricsSamplingCenter {
  static let shared = ProcessMetricsSamplingCenter()

  typealias ResetProvider = @Sendable () async -> Void
  typealias SampleProvider =
    @Sendable ([RunningApplicationDescriptor]) async -> ProcessMetricsSnapshot
  typealias RunningApplicationsProvider =
    @Sendable () async -> [RunningApplicationDescriptor]

  private struct Subscription {
    let minimumInterval: TimeInterval
    let continuation: AsyncStream<ProcessMetricsSnapshot>.Continuation
    var lastDeliveredAt: Date?
  }

  private let resetProvider: ResetProvider
  private let sampleProvider: SampleProvider
  private let runningApplicationsProvider: RunningApplicationsProvider
  private var subscribers: [UUID: Subscription] = [:]
  private var cachedSnapshot: ProcessMetricsSnapshot = .empty
  private var samplingTask: Task<Void, Never>?
  private var resetTask: Task<Void, Never>?
  private var clockGeneration: UInt64 = 0

  init() {
    let provider = ProcessMetricsProvider()
    resetProvider = { await provider.reset() }
    sampleProvider = { applications in
      await provider.sample(runningApplications: applications)
    }
    runningApplicationsProvider = {
      await MainActor.run {
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
  }

  init(
    resetProvider: @escaping ResetProvider,
    sampleProvider: @escaping SampleProvider,
    runningApplicationsProvider: @escaping RunningApplicationsProvider
  ) {
    self.resetProvider = resetProvider
    self.sampleProvider = sampleProvider
    self.runningApplicationsProvider = runningApplicationsProvider
  }

  func subscribe(_ id: UUID, minimumInterval: TimeInterval) async
    -> AsyncStream<ProcessMetricsSnapshot>
  {
    let interval = normalizedInterval(minimumInterval)
    let previousMinimum = activeMinimumInterval()
    let wasIdle = subscribers.isEmpty

    if let replaced = subscribers.removeValue(forKey: id) {
      replaced.continuation.finish()
    }

    let pair = AsyncStream<ProcessMetricsSnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    var subscription = Subscription(
      minimumInterval: interval,
      continuation: pair.continuation,
      lastDeliveredAt: nil)

    if !wasIdle,
      ProcessSamplingCachePolicy.isFresh(
        timestamp: cachedSnapshot.timestamp,
        now: Date(),
        minimumInterval: interval)
    {
      pair.continuation.yield(cachedSnapshot)
      subscription.lastDeliveredAt = cachedSnapshot.timestamp
    }
    subscribers[id] = subscription

    if wasIdle {
      cachedSnapshot = .empty
      await resetProviderForNewSession()
      guard !subscribers.isEmpty else { return pair.stream }
      startSamplingLoop()
    } else if cadenceChanged(from: previousMinimum, to: activeMinimumInterval()) {
      restartSamplingLoop()
    } else if samplingTask == nil, resetTask == nil {
      startSamplingLoop()
    }

    return pair.stream
  }

  func unsubscribe(_ id: UUID) {
    let previousMinimum = activeMinimumInterval()
    guard let removed = subscribers.removeValue(forKey: id) else { return }
    removed.continuation.finish()

    guard !subscribers.isEmpty else {
      stopSamplingLoop(clearCache: true)
      return
    }

    if cadenceChanged(from: previousMinimum, to: activeMinimumInterval()) {
      restartSamplingLoop()
    }
  }

  private func resetProviderForNewSession() async {
    if let activeReset = resetTask {
      await activeReset.value
      return
    }

    let resetProvider = self.resetProvider
    let operation = Task { await resetProvider() }
    resetTask = operation
    await operation.value
    resetTask = nil
  }

  private func startSamplingLoop() {
    guard samplingTask == nil, !subscribers.isEmpty else { return }
    clockGeneration &+= 1
    let generation = clockGeneration
    samplingTask = Task { [weak self] in
      await self?.runSamplingLoop(generation: generation)
    }
  }

  private func restartSamplingLoop() {
    clockGeneration &+= 1
    samplingTask?.cancel()
    samplingTask = nil
    guard !subscribers.isEmpty else { return }
    let generation = clockGeneration
    samplingTask = Task { [weak self] in
      await self?.runSamplingLoop(generation: generation)
    }
  }

  private func stopSamplingLoop(clearCache: Bool) {
    clockGeneration &+= 1
    samplingTask?.cancel()
    samplingTask = nil
    if clearCache {
      cachedSnapshot = .empty
    }
  }

  private func runSamplingLoop(generation: UInt64) async {
    while !Task.isCancelled {
      guard generation == clockGeneration, !subscribers.isEmpty else { return }

      let applications = await runningApplicationsProvider()
      guard !Task.isCancelled, generation == clockGeneration, !subscribers.isEmpty else {
        return
      }

      let snapshot = await sampleProvider(applications)
      guard !Task.isCancelled, generation == clockGeneration, !subscribers.isEmpty else {
        return
      }

      cachedSnapshot = snapshot
      publish(snapshot)

      guard let interval = activeMinimumInterval() else { return }
      do {
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
      } catch {
        return
      }
    }
  }

  private func publish(_ snapshot: ProcessMetricsSnapshot) {
    for id in Array(subscribers.keys) {
      guard var subscription = subscribers[id] else { continue }
      let shouldDeliver: Bool
      if let previous = subscription.lastDeliveredAt {
        let elapsed = snapshot.timestamp.timeIntervalSince(previous)
        shouldDeliver = elapsed < 0 || elapsed >= subscription.minimumInterval
      } else {
        shouldDeliver = true
      }

      guard shouldDeliver else { continue }
      subscription.continuation.yield(snapshot)
      subscription.lastDeliveredAt = snapshot.timestamp
      subscribers[id] = subscription
    }
  }

  private func activeMinimumInterval() -> TimeInterval? {
    subscribers.values.map(\.minimumInterval).min()
  }

  private func cadenceChanged(from previous: TimeInterval?, to current: TimeInterval?) -> Bool {
    switch (previous, current) {
    case (nil, nil): return false
    case let (left?, right?): return abs(left - right) > 0.000_1
    default: return true
    }
  }

  private func normalizedInterval(_ interval: TimeInterval) -> TimeInterval {
    guard interval.isFinite else { return 1 }
    return min(30, max(0.25, interval))
  }
}

@MainActor
final class ProcessConsumersMonitor: ObservableObject {
  @Published private(set) var snapshot: ProcessMetricsSnapshot = .empty
  @Published private(set) var isRunning = false

  private let center = ProcessMetricsSamplingCenter.shared
  private var task: Task<Void, Never>?

  func start(interval: TimeInterval) {
    guard task == nil else { return }
    isRunning = true
    let refreshInterval = min(30, max(1, interval))
    let subscriberID = UUID()
    task = Task { [weak self, center] in
      let stream = await center.subscribe(
        subscriberID,
        minimumInterval: refreshInterval)

      for await next in stream {
        if Task.isCancelled { break }
        guard let self else { break }
        self.snapshot = next
      }

      await center.unsubscribe(subscriberID)
    }
  }

  func restart(interval: TimeInterval) {
    let previous = task
    previous?.cancel()
    task = nil
    isRunning = false

    isRunning = true
    let refreshInterval = min(30, max(1, interval))
    let subscriberID = UUID()
    task = Task { [weak self, center] in
      await previous?.value
      guard !Task.isCancelled else { return }

      let stream = await center.subscribe(
        subscriberID,
        minimumInterval: refreshInterval)
      for await next in stream {
        if Task.isCancelled { break }
        guard let self else { break }
        self.snapshot = next
      }
      await center.unsubscribe(subscriberID)
    }
  }

  func stop() {
    task?.cancel()
    task = nil
    isRunning = false
  }

  deinit {
    task?.cancel()
  }
}

struct ProcessConsumersView: View {
  @ObservedObject var monitor: ProcessConsumersMonitor
  let metric: ProcessConsumerMetric
  @State private var visibleCount = 5
  @State private var applicationIcons: [pid_t: NSImage] = [:]

  @MainActor
  private static let percentFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 1
    formatter.minimumFractionDigits = 1
    return formatter
  }()

  var body: some View {
    let ranked = rankedApplications

    return VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 8) {
        Label(title, systemImage: symbol)
          .font(.subheadline.bold())
        if isEstimated {
          Text(L10n.string("Estimated"))
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: Capsule())
        }
        Spacer()
        Picker(L10n.string("Application count"), selection: $visibleCount) {
          Text("5").tag(5)
          Text("10").tag(10)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 86)
      }

      if ranked.isEmpty {
        VStack(spacing: 7) {
          ProgressView()
            .controlSize(.small)
          Text(L10n.string("Collecting application activity"))
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(L10n.string("CPU and energy deltas appear after the second sample."))
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 145)
      } else {
        ScrollView {
          LazyVStack(spacing: 6) {
            ForEach(Array(ranked.prefix(visibleCount).enumerated()), id: \.element.id) {
              index, application in
              applicationRow(application, rank: index + 1)
            }
          }
          .padding(.vertical, 1)
        }
        .frame(minHeight: 150, maxHeight: 245)
      }

      Label(note, systemImage: noteSymbol)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(11)
    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(.quaternary.opacity(0.35), lineWidth: 1))
    .accessibilityIdentifier("processConsumers.\(metric.rawValue)")
    .onReceive(monitor.$snapshot) { _ in
      refreshApplicationIcons()
    }
  }

  private func applicationRow(_ application: ApplicationProcessUsage, rank: Int) -> some View {
    HStack(spacing: 9) {
      Text("\(rank)")
        .font(.caption.monospacedDigit().bold())
        .foregroundStyle(.secondary)
        .frame(width: 18, alignment: .trailing)

      applicationIcon(application)
        .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(application.name)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        HStack(spacing: 5) {
          Text(processCountText(application.processCount))
          Text("·")
          Text(secondaryValue(application))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 4) {
        Text(primaryValue(application))
          .font(.subheadline.monospacedDigit().bold())
        if metric == .gpu || metric == .energy {
          ProgressView(value: score(application), total: 100)
            .progressViewStyle(.linear)
            .frame(width: 86)
        }
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 9))
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func applicationIcon(_ application: ApplicationProcessUsage) -> some View {
    if let icon = applicationIcons[application.representativePID] {
      Image(nsImage: icon)
        .resizable()
        .scaledToFit()
        .accessibilityHidden(true)
    } else {
      Image(systemName: "app.dashed")
        .font(.title3)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
  }

  private var rankedApplications: [ApplicationProcessUsage] {
    monitor.snapshot.applications
      .filter { application in
        application.memoryBytes > 1_048_576
          || application.cpuPercent > 0.01
          || application.energyImpactScore > 0.01
          || application.gpuActivityScore > 0.01
      }
      .sorted { lhs, rhs in
        let left = sortValue(lhs)
        let right = sortValue(rhs)
        if left == right {
          return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return left > right
      }
  }

  private func sortValue(_ application: ApplicationProcessUsage) -> Double {
    switch metric {
    case .cpu: return application.cpuPercent
    case .memory: return Double(application.memoryBytes)
    case .gpu: return application.gpuActivityScore
    case .energy: return application.energyWatts ?? application.energyImpactScore
    }
  }

  private func score(_ application: ApplicationProcessUsage) -> Double {
    switch metric {
    case .gpu: return application.gpuActivityScore
    case .energy: return application.energyImpactScore
    case .cpu, .memory: return 0
    }
  }

  private func primaryValue(_ application: ApplicationProcessUsage) -> String {
    switch metric {
    case .cpu:
      return decimalPercent(application.cpuPercent)
    case .memory:
      return byteCount(application.memoryBytes)
    case .gpu:
      return L10n.format("%.0f score", application.gpuActivityScore)
    case .energy:
      if let watts = application.energyWatts {
        return L10n.format("≈ %.2f W", watts)
      }
      return L10n.format("%.0f impact", application.energyImpactScore)
    }
  }

  private func secondaryValue(_ application: ApplicationProcessUsage) -> String {
    switch metric {
    case .cpu:
      return byteCount(application.memoryBytes)
    case .memory:
      return L10n.format("CPU %@", decimalPercent(application.cpuPercent))
    case .gpu:
      return L10n.format("CPU %@", decimalPercent(application.cpuPercent))
    case .energy:
      if application.isEnergyEstimated {
        return L10n.string("CPU, memory and disk estimate")
      }
      return L10n.string("Kernel energy accounting")
    }
  }

  private var title: String {
    switch metric {
    case .cpu: return L10n.string("Top CPU applications")
    case .memory: return L10n.string("Top memory applications")
    case .gpu: return L10n.string("Top GPU applications")
    case .energy: return L10n.string("Top energy applications")
    }
  }

  private var symbol: String {
    switch metric {
    case .cpu: return "cpu"
    case .memory: return "memorychip"
    case .gpu: return "rectangle.3.group.fill"
    case .energy: return "battery.100percent.bolt"
    }
  }

  private var isEstimated: Bool {
    switch metric {
    case .gpu: return true
    case .energy: return !monitor.snapshot.energyCountersAvailable
    case .cpu, .memory: return false
    }
  }

  private var note: String {
    switch metric {
    case .cpu:
      return L10n.string("Application helpers are grouped under their parent app. CPU use can exceed 100% on multicore Macs.")
    case .memory:
      return L10n.string("Memory uses physical footprint and combines helper processes belonging to the same app.")
    case .gpu:
      return L10n.string("macOS does not expose public per-app GPU percentages. This ranking is a relative estimate from energy counters and graphics helper activity.")
    case .energy:
      return L10n.string("This is current energy impact, not historical battery drain. Exact battery watts per app are not exposed by macOS.")
    }
  }

  private var noteSymbol: String {
    switch metric {
    case .cpu, .memory: return "info.circle"
    case .gpu, .energy: return "exclamationmark.triangle"
    }
  }

  @MainActor
  private func decimalPercent(_ value: Double) -> String {
    "\(Self.percentFormatter.string(from: NSNumber(value: value)) ?? "0.0")%"
  }

  private func byteCount(_ value: UInt64) -> String {
    ByteCountFormatter.string(
      fromByteCount: Int64(clamping: value),
      countStyle: .memory)
  }

  private func processCountText(_ count: Int) -> String {
    count == 1 ? L10n.string("1 process") : L10n.format("%d processes", count)
  }

  @MainActor
  private func refreshApplicationIcons() {
    var icons: [pid_t: NSImage] = [:]
    icons.reserveCapacity(monitor.snapshot.applications.count)
    for application in NSWorkspace.shared.runningApplications {
      guard !application.isTerminated,
        application.processIdentifier > 0,
        let icon = application.icon
      else {
        continue
      }
      icons[application.processIdentifier] = icon
    }
    applicationIcons = icons
  }
}