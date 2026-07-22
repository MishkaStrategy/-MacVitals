import Charts
import SwiftUI

struct OverviewView: View {
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        VStack(alignment: .leading) {
          Text("MacVitals").font(.title2.bold())
          Text("Privacy-first Mac diagnostics").foregroundStyle(.secondary)
        }
        Spacer()
        Button { openSettings() } label: { Image(systemName: "gearshape") }
          .buttonStyle(.plain)
          .accessibilityLabel("Preferences")
      }
      LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
        MetricCard(
          title: "CPU", value: percent(coordinator.snapshot.cpu.value?.total), symbol: "cpu")
        MetricCard(
          title: "Memory", value: percent(coordinator.snapshot.memory.value?.usedPercent),
          symbol: "memorychip")
        MetricCard(title: "GPU", value: gpuText, symbol: "rectangle.3.group")
        MetricCard(title: "Battery", value: batteryText, symbol: "battery.75percent")
      }
      memorySummary
      PowerFlowView(snapshot: coordinator.snapshot)
      history
      HStack {
        Text(coordinator.snapshot.power.value?.explanation ?? "Collecting data")
          .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        Spacer()
      }
      Divider()
      HStack {
        Button("Diagnostics") { exportDiagnostics() }
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }
      }
    }
    .padding(16)
    .frame(width: 390, height: 590)
    .accessibilityElement(children: .contain)
  }

  private var memorySummary: some View {
    HStack(spacing: 8) {
      Image(systemName: "externaldrive")
        .foregroundStyle(.secondary)
      Text(memorySummaryText)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .accessibilityLabel("Memory and swap details")
    .accessibilityValue(memorySummaryText)
  }

  private var history: some View {
    Chart(coordinator.cpuHistory.suffix(60)) { point in
      if let value = point.value {
        LineMark(x: .value("Time", point.timestamp), y: .value("CPU", value))
      }
    }
    .chartYScale(domain: 0...100)
    .frame(height: 76)
    .accessibilityLabel("CPU history")
  }

  private var memorySummaryText: String {
    guard let memory = coordinator.snapshot.memory.value else { return "Memory data unavailable" }
    let used = formattedBytes(memory.usedBytes)
    let physical = formattedBytes(memory.physicalBytes)
    if let swap = memory.swapUsedBytes {
      return "RAM \(used) / \(physical) · Swap \(formattedBytes(swap))"
    }
    return "RAM \(used) / \(physical) · Swap unavailable"
  }

  private var gpuText: String {
    coordinator.snapshot.gpu.value?.systemUtilizationPercent.map(percent) ?? "Unavailable"
  }

  private var batteryText: String {
    coordinator.snapshot.battery.value?.percentage.map(percent) ?? "No battery"
  }

  private func percent(_ value: Double?) -> String {
    value.map { "\(Int($0.rounded()))%" } ?? "—"
  }

  private func formattedBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
  }

  private func openSettings() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func exportDiagnostics() {
    DiagnosticReportBuilder.export(snapshot: coordinator.snapshot)
  }
}

private struct MetricCard: View {
  let title: LocalizedStringKey
  let value: String
  let symbol: String

  var body: some View {
    HStack {
      Image(systemName: symbol).frame(width: 24)
      VStack(alignment: .leading) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.headline.monospacedDigit())
      }
      Spacer()
    }
    .padding(10)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
  }
}
