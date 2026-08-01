import AppKit
import Combine
import SwiftUI

struct HistoricalConsumptionLeadersView: View {
  @EnvironmentObject private var settings: SettingsStore
  @ObservedObject private var center: HistoricalConsumptionCenter
  @State private var selectedRange: HistoricalConsumptionRange = .oneHour
  @State private var leaders: [HistoricalConsumptionLeader] = []
  @State private var coverageDuration: TimeInterval = 0
  @State private var visibleCount = 10
  @State private var isLoading = true

  let metric: HistoricalConsumptionMetric

  init(
    metric: HistoricalConsumptionMetric,
    center: HistoricalConsumptionCenter = .shared
  ) {
    self.metric = metric
    self.center = center
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      controls

      if metric == .network {
        networkUnavailable
      } else if isLoading && leaders.isEmpty {
        collectingState
      } else if leaders.isEmpty {
        emptyState
      } else {
        leaderList
      }

      Label(
        ConsumptionHistoryL10n.string("History is collected while MacVitals is running."),
        systemImage: "info.circle")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding(12)
    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(.quaternary.opacity(0.35), lineWidth: 1))
    .task { await reload() }
    .onChange(of: selectedRange) { _ in
      Task { await reload() }
    }
    .onReceive(
      center.$revision
        .removeDuplicates()
        .throttle(
          for: .seconds(max(1, settings.samplingInterval)),
          scheduler: RunLoop.main,
          latest: true)
    ) { _ in
      Task { await reload() }
    }
  }

  private var controls: some View {
    HStack(spacing: 10) {
      Label(
        ConsumptionHistoryL10n.string("Top applications"),
        systemImage: "list.number")
        .font(.subheadline.bold())

      if isEstimated {
        Text(ConsumptionHistoryL10n.string("Estimated"))
          .font(.caption2.bold())
          .foregroundStyle(.secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(.quaternary.opacity(0.5), in: Capsule())
      }

      Spacer(minLength: 8)

      Text("\(ConsumptionHistoryL10n.string("History coverage")): \(coverageText)")
        .font(.caption2)
        .foregroundStyle(.secondary)

      Picker("Range", selection: $selectedRange) {
        ForEach(HistoricalConsumptionRange.allCases) { range in
          Text(range.title).tag(range)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 230)

      Picker(L10n.string("Application count"), selection: $visibleCount) {
        Text("5").tag(5)
        Text("10").tag(10)
        Text("20").tag(20)
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 118)
    }
  }

  private var leaderList: some View {
    ScrollView {
      LazyVStack(spacing: 7) {
        ForEach(Array(leaders.prefix(visibleCount).enumerated()), id: \.element.id) {
          index, leader in
          leaderRow(leader, rank: index + 1)
        }
      }
      .padding(.vertical, 1)
    }
    .frame(minHeight: 330, maxHeight: 490)
  }

  private func leaderRow(
    _ leader: HistoricalConsumptionLeader,
    rank: Int
  ) -> some View {
    HStack(spacing: 10) {
      Text("\(rank)")
        .font(.caption.monospacedDigit().bold())
        .foregroundStyle(.secondary)
        .frame(width: 22, alignment: .trailing)

      applicationIcon(leader)
        .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 3) {
        Text(leader.name)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        Text(secondaryValue(leader))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 10)

      Text(primaryValue(leader))
        .font(.subheadline.monospacedDigit().bold())
        .multilineTextAlignment(.trailing)
        .lineLimit(2)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 8)
    .background(Color.secondary.opacity(0.065), in: RoundedRectangle(cornerRadius: 9))
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func applicationIcon(_ leader: HistoricalConsumptionLeader) -> some View {
    if let icon = resolvedIcon(leader) {
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

  private func resolvedIcon(_ leader: HistoricalConsumptionLeader) -> NSImage? {
    if let application = NSWorkspace.shared.runningApplications.first(where: {
      $0.processIdentifier == leader.representativePID
    }), let icon = application.icon {
      return icon
    }
    if let bundleIdentifier = leader.bundleIdentifier,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    {
      return NSWorkspace.shared.icon(forFile: url.path)
    }
    return nil
  }

  private var collectingState: some View {
    VStack(spacing: 9) {
      ProgressView().controlSize(.small)
      Text(ConsumptionHistoryL10n.string("Collecting historical activity"))
        .font(.subheadline.bold())
      Text(ConsumptionHistoryL10n.string("History is collected while MacVitals is running."))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 350)
  }

  private var emptyState: some View {
    VStack(spacing: 9) {
      Image(systemName: "clock.badge.questionmark")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text(ConsumptionHistoryL10n.string("No historical activity in this interval"))
        .font(.subheadline.bold())
    }
    .frame(maxWidth: .infinity, minHeight: 350)
  }

  private var networkUnavailable: some View {
    VStack(spacing: 10) {
      Image(systemName: "network.slash")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text(ConsumptionHistoryL10n.string("Per-application network history unavailable"))
        .font(.headline)
      Text(
        ConsumptionHistoryL10n.string(
          "macOS interface counters do not identify which application transferred the bytes."))
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 460)
    }
    .frame(maxWidth: .infinity, minHeight: 350)
  }

  private func primaryValue(_ leader: HistoricalConsumptionLeader) -> String {
    switch metric {
    case .cpu:
      return durationText(leader.cpuCoreSeconds)
    case .memory:
      return byteCount(leader.averageMemoryBytes)
    case .gpu:
      return L10n.format("%.1f score", leader.averageGPUScore)
    case .energy:
      if leader.directEnergyJoules > 0 {
        return L10n.format("%.3f Wh", leader.directEnergyJoules / 3_600)
      }
      return L10n.format("%.1f impact", leader.averageEnergyImpact)
    case .disk:
      return fileByteCount(leader.diskBytes)
    case .thermal:
      return L10n.format("%.1f impact", leader.averageThermalScore)
    case .network:
      return "—"
    }
  }

  private func secondaryValue(_ leader: HistoricalConsumptionLeader) -> String {
    switch metric {
    case .cpu:
      let average = leader.observedSeconds > 0
        ? leader.cpuCoreSeconds / leader.observedSeconds * 100 : 0
      return L10n.format("Average %.1f%% · %d processes", average, leader.processCountPeak)
    case .memory:
      return "\(ConsumptionHistoryL10n.string("Peak")) \(byteCount(leader.memoryPeakBytes))"
    case .gpu:
      return ConsumptionHistoryL10n.string("Average GPU activity")
    case .energy:
      return leader.directEnergyJoules > 0
        ? ConsumptionHistoryL10n.string("Measured energy")
        : ConsumptionHistoryL10n.string("Energy impact")
    case .disk:
      return ConsumptionHistoryL10n.string("Disk activity")
    case .thermal:
      return ConsumptionHistoryL10n.string("Thermal impact")
    case .network:
      return ""
    }
  }

  private var isEstimated: Bool {
    switch metric {
    case .gpu, .energy, .thermal, .network: return true
    case .cpu, .memory, .disk: return false
    }
  }

  private var coverageText: String {
    if coverageDuration < 60 { return "—" }
    if coverageDuration < 3_600 {
      return L10n.format("%d min", Int(coverageDuration / 60))
    }
    if coverageDuration < 86_400 {
      return L10n.format("%.1f h", coverageDuration / 3_600)
    }
    return L10n.format("%.1f d", coverageDuration / 86_400)
  }

  private func durationText(_ seconds: Double) -> String {
    let bounded = max(0, seconds)
    if bounded < 60 { return L10n.format("%.0f s", bounded) }
    if bounded < 3_600 { return L10n.format("%.1f min", bounded / 60) }
    return L10n.format("%.2f h", bounded / 3_600)
  }

  private func byteCount(_ value: UInt64) -> String {
    ByteCountFormatter.string(
      fromByteCount: Int64(clamping: value),
      countStyle: .memory)
  }

  private func fileByteCount(_ value: Double) -> String {
    let bounded = UInt64(min(Double(UInt64.max), max(0, value)).rounded())
    return NetworkByteFormatter.bytes(bounded)
  }

  @MainActor
  private func reload() async {
    isLoading = true
    async let loadedLeaders = center.leaders(metric: metric, range: selectedRange)
    async let loadedCoverage = center.coverageDuration(range: selectedRange)
    leaders = await loadedLeaders
    coverageDuration = await loadedCoverage
    isLoading = false
  }
}
