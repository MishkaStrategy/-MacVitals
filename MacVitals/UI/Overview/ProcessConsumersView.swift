import AppKit
import Combine
import SwiftUI

actor ProcessMetricsSamplingCenter {
  static let shared = ProcessMetricsSamplingCenter()

  private let provider = ProcessMetricsProvider()
  private var subscribers: Set<UUID> = []
  private var cachedSnapshot: ProcessMetricsSnapshot = .empty
  private var inFlight: Task<ProcessMetricsSnapshot, Never>?

  func subscribe(_ id: UUID) async {
    let wasIdle = subscribers.isEmpty
    subscribers.insert(id)
    if wasIdle {
      cachedSnapshot = .empty
      await provider.reset()
    }
  }

  func unsubscribe(_ id: UUID) {
    subscribers.remove(id)
    if subscribers.isEmpty {
      cachedSnapshot = .empty
      inFlight?.cancel()
      inFlight = nil
    }
  }

  func sample(
    runningApplications: [RunningApplicationDescriptor],
    minimumInterval: TimeInterval
  ) async -> ProcessMetricsSnapshot {
    let freshnessWindow = max(0.25, minimumInterval * 0.8)
    if cachedSnapshot.timestamp != .distantPast,
      Date().timeIntervalSince(cachedSnapshot.timestamp) < freshnessWindow
    {
      return cachedSnapshot
    }

    if let inFlight {
      return await inFlight.value
    }

    let provider = self.provider
    let task = Task {
      await provider.sample(runningApplications: runningApplications)
    }
    inFlight = task
    let snapshot = await task.value
    cachedSnapshot = snapshot
    inFlight = nil
    return snapshot
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
      await center.subscribe(subscriberID)
      defer {
        Task { await center.unsubscribe(subscriberID) }
      }

      while !Task.isCancelled {
        guard let self else { break }
        let applications = self.runningApplicationDescriptors()
        let next = await center.sample(
          runningApplications: applications,
          minimumInterval: refreshInterval)
        guard !Task.isCancelled else { break }
        self.snapshot = next
        let nanoseconds = UInt64(refreshInterval * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
      }
    }
  }

  func restart(interval: TimeInterval) {
    stop()
    start(interval: interval)
  }

  func stop() {
    task?.cancel()
    task = nil
    isRunning = false
  }

  deinit {
    task?.cancel()
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
