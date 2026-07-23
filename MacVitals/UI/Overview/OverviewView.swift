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
        Button {
          openSettings()
        } label: {
          Image(systemName: "gearshape")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preferences")
      }
      LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
        MetricCard(
          title: "CPU",
          value: MetricNumberFormatter.percentage(coordinator.snapshot.cpu.value?.total),
          symbol: "cpu")
        MetricCard(
          title: "Memory",
          value: MetricNumberFormatter.percentage(coordinator.snapshot.memory.value?.usedPercent),
          symbol: "memorychip")
        MetricCard(title: "GPU", value: gpuText, symbol: "rectangle.3.group")
        MetricCard(title: "Battery", value: batteryText, symbol: "battery.75percent")
      }
      memorySummary
      gpuSummary
      PowerFlowView(snapshot: coordinator.snapshot)
      history
      HStack {
        Text(coordinator.snapshot.power.value?.explanation ?? L10n.string("Collecting data"))
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
    .frame(width: 390, height: 630)
    .accessibilityElement(children: .contain)
  }

  private var memorySummary: some View {
    HStack(spacing: 8) {
      Image(systemName: memoryPressureSymbol)
        .foregroundStyle(.secondary)
      Text(memorySummaryText)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Spacer(minLength: 0)
    }
    .accessibilityLabel("Memory, swap and pressure details")
    .accessibilityValue(memorySummaryText)
  }

  private var gpuSummary: some View {
    HStack(spacing: 8) {
      Image(systemName: "display")
        .foregroundStyle(.secondary)
      Text(gpuSummaryText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .accessibilityLabel("GPU details")
    .accessibilityValue(gpuSummaryText)
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
    guard let memory = coordinator.snapshot.memory.value else {
      return L10n.string("Memory data unavailable")
    }
    let used = formattedBytes(memory.usedBytes)
    let physical = formattedBytes(memory.physicalBytes)
    let swap = memory.swapUsedBytes.map(formattedBytes) ?? L10n.string("Unavailable")
    return L10n.format(
      "RAM %@ / %@ · Swap %@\nPressure: %@",
      used,
      physical,
      swap,
      memoryPressureText(memory.pressureLevel))
  }

  private var memoryPressureSymbol: String {
    switch coordinator.snapshot.memory.value?.pressureLevel {
    case .critical: return "exclamationmark.triangle.fill"
    case .warning: return "exclamationmark.triangle"
    case .normal: return "checkmark.circle"
    default: return "questionmark.circle"
    }
  }

  private func memoryPressureText(_ level: MemoryPressureLevel) -> String {
    switch level {
    case .normal: return L10n.string("Normal")
    case .warning: return L10n.string("Warning")
    case .critical: return L10n.string("Critical")
    case .unknown: return L10n.string("Unknown")
    }
  }

  private var gpuText: String {
    guard let gpu = coordinator.snapshot.gpu.value else { return L10n.string("Unavailable") }
    if let utilization = gpu.systemUtilizationPercent {
      return MetricNumberFormatter.percentage(utilization)
    }
    return L10n.string(gpu.metalAvailable ? "Metal" : "Unavailable")
  }

  private var gpuSummaryText: String {
    guard let gpu = coordinator.snapshot.gpu.value else {
      return L10n.string("GPU data unavailable")
    }
    let name = gpu.name ?? L10n.string("Unknown GPU")
    let memory = L10n.string(
      gpu.hasUnifiedMemory == true ? "unified memory" : "discrete memory")
    return L10n.format("%@ · %@ · utilization unavailable", name, memory)
  }

  private var batteryText: String {
    BatteryDisplayText.summary(coordinator.snapshot.battery)
  }

  private func formattedBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
  }

  private func openSettings() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func exportDiagnostics() {
    DiagnosticReportBuilder.export(
      snapshot: coordinator.snapshot,
      samplingHealth: coordinator.samplingHealth)
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
