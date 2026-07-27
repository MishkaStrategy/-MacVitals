import Charts
import SwiftUI

nonisolated enum OverviewLayout {
  static let width: CGFloat = 390
  static let height: CGFloat = 720
}

struct OverviewView: View {
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var settings: SettingsStore
  @EnvironmentObject private var fanControl: FanControlClient
  @State private var selectedDetail: MetricDetailKind?

  var body: some View {
    VStack(spacing: 10) {
      HStack {
        VStack(alignment: .leading) {
          Text("MacVitals").font(.title2.bold())
          Text("Privacy-first Mac diagnostics").foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          selectedDetail = nil
          PreferencesWindowPresenter.shared.show(
            coordinator: coordinator,
            settings: settings,
            fanControl: fanControl)
        } label: {
          Image(systemName: "gearshape")
        }
        .buttonStyle(.plain)
        .help("Preferences")
        .accessibilityLabel("Preferences")
      }
      LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
        MetricCard(
          title: "CPU",
          value: MetricNumberFormatter.percentage(coordinator.snapshot.cpu.value?.total),
          symbol: "cpu",
          action: { selectedDetail = .cpu })
        MetricCard(
          title: "Memory",
          value: MetricNumberFormatter.percentage(coordinator.snapshot.memory.value?.usedPercent),
          symbol: "memorychip",
          action: { selectedDetail = .memory })
        MetricCard(
          title: "GPU",
          value: gpuText,
          symbol: "rectangle.3.group",
          action: { selectedDetail = .gpu })
        MetricCard(
          title: "Battery",
          value: batteryText,
          symbol: "battery.75percent",
          action: { selectedDetail = .battery })
        MetricCard(
          title: LocalizedStringKey(TemperatureL10n.string("Temperature")),
          value: temperatureText,
          symbol: "thermometer.medium",
          action: { selectedDetail = .temperature })
        MetricCard(
          title: "Fans",
          value: FanDisplayText.summary(coordinator.snapshot.fans),
          symbol: "fan",
          action: { selectedDetail = .fans })
      }
      memorySummary
      gpuSummary
      PowerFlowView(snapshot: coordinator.snapshot)
      history
      Divider()
      HStack {
        Button("Diagnostics") { exportDiagnostics() }
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }
      }
    }
    .padding(16)
    .frame(width: OverviewLayout.width, height: OverviewLayout.height)
    .accessibilityElement(children: .contain)
    .popover(
      isPresented: Binding(
        get: { selectedDetail != nil },
        set: { isPresented in
          if !isPresented { selectedDetail = nil }
        }),
      attachmentAnchor: .rect(.bounds),
      arrowEdge: .trailing
    ) {
      if let selectedDetail {
        MetricDetailView(kind: selectedDetail)
          .environmentObject(coordinator)
          .environmentObject(fanControl)
      }
    }
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
    let points = HistoryChartSegmentation.points(
      from: Array(coordinator.cpuHistory.suffix(360)))
    return VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("CPU history")
          .font(.caption.bold())
        Spacer()
        Text("30 min · 5 s")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Chart(points) { point in
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value("CPU", point.value),
          series: .value("Sampling epoch", point.segment)
        )
        .foregroundStyle(Color.accentColor)
      }
      .chartYScale(domain: 0...100)
      .chartXAxis {
        AxisMarks(values: .stride(by: .minute, count: 5)) { value in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
          AxisTick()
          AxisValueLabel(format: .dateTime.hour().minute())
        }
      }
      .chartPlotStyle { plotArea in
        plotArea
          .background(.quaternary.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .frame(height: 106)
      .accessibilityLabel("CPU history")
    }
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
    MetricNumberFormatter.percentage(coordinator.snapshot.gpu.value?.systemUtilizationPercent)
  }

  private var gpuSummaryText: String {
    guard let gpu = coordinator.snapshot.gpu.value else {
      return L10n.string("GPU data unavailable")
    }
    let name = gpu.name ?? L10n.string("Unknown GPU")
    let memory = GPUMemoryDisplayText.summary(hasUnifiedMemory: gpu.hasUnifiedMemory)
    let utilization = MetricNumberFormatter.percentage(gpu.systemUtilizationPercent)
    let utilizationText = utilization == "—" ? gpu.utilizationAvailability.displayName : utilization
    return "\(name) · \(memory) · \(utilizationText)"
  }

  private var batteryText: String {
    BatteryDisplayText.summary(coordinator.snapshot.battery)
  }

  private var temperatureText: String {
    guard let value = coordinator.snapshot.temperature.value?.processorCelsius
      ?? coordinator.snapshot.temperature.value?.maximumCelsius
    else { return "—" }
    return L10n.format("%.1f °C", value)
  }

  private func formattedBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
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
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack {
        Image(systemName: symbol).frame(width: 24)
        VStack(alignment: .leading) {
          Text(title).font(.caption).foregroundStyle(.secondary)
          Text(value).font(.headline.monospacedDigit()).lineLimit(1)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.bold())
          .foregroundStyle(.tertiary)
      }
      .padding(10)
      .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
      .contentShape(RoundedRectangle(cornerRadius: 10))
    }
    .buttonStyle(.plain)
  }
}
