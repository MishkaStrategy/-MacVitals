import Charts
import SwiftUI

nonisolated enum OverviewLayout {
  static let width: CGFloat = 410
  static let height: CGFloat = 740
}

struct OverviewView: View {
  @Environment(\.appTheme) private var theme
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var settings: SettingsStore
  @EnvironmentObject private var fanControl: FanControlClient
  @State private var selectedDetail: MetricDetailKind?

  var body: some View {
    VStack(spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("MacVitals").font(.title2.bold())
          HStack(spacing: 6) {
            Circle()
              .fill(coordinator.isRunning ? Color.green : Color.orange)
              .frame(width: 7, height: 7)
            Text(coordinator.isRunning ? L10n.string("Live monitoring") : L10n.string("Monitoring paused"))
              .foregroundStyle(.secondary)
            Text("·")
              .foregroundStyle(.tertiary)
            Text(L10n.format("Every %g s", settings.samplingInterval))
              .foregroundStyle(.secondary)
          }
          .font(.caption)
        }
        Spacer()
        Button {
          selectedDetail = nil
          PreferencesWindowPresenter.shared.show(
            coordinator: coordinator,
            settings: settings,
            fanControl: fanControl)
        } label: {
          Image(systemName: "gearshape.fill")
            .font(.title3)
            .padding(7)
            .background(.quaternary.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Preferences")
        .accessibilityLabel("Preferences")
      }

      LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
        MetricCard(
          title: "CPU",
          value: MetricNumberFormatter.percentage(coordinator.snapshot.cpu.value?.total),
          symbol: "cpu.fill",
          kind: .cpu,
          action: { selectedDetail = .cpu })
        MetricCard(
          title: "Memory",
          value: MetricNumberFormatter.percentage(coordinator.snapshot.memory.value?.usedPercent),
          symbol: "memorychip.fill",
          kind: .memory,
          action: { selectedDetail = .memory })
        MetricCard(
          title: "GPU",
          value: gpuText,
          symbol: "rectangle.3.group.fill",
          kind: .gpu,
          action: { selectedDetail = .gpu })
        MetricCard(
          title: "Battery",
          value: batteryText,
          symbol: batterySymbol,
          kind: .battery,
          action: { selectedDetail = .battery })
        MetricCard(
          title: LocalizedStringKey(TemperatureL10n.string("Temperature")),
          value: temperatureText,
          symbol: "thermometer.high",
          kind: .temperature,
          action: { selectedDetail = .temperature })
        MetricCard(
          title: "Fans",
          value: FanDisplayText.summary(coordinator.snapshot.fans),
          symbol: "fan.fill",
          kind: .fans,
          action: { selectedDetail = .fans })
      }

      memorySummary
      gpuSummary
      PowerFlowView(snapshot: coordinator.snapshot) { selectedDetail = .power }
        .tint(theme.color(for: .systemPower))
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
          .environmentObject(settings)
          .environmentObject(fanControl)
          .tint(theme.color(for: selectedDetail.themeMetricKind))
      }
    }
  }

  private var memorySummary: some View {
    HStack(spacing: 8) {
      Image(systemName: memoryPressureSymbol)
        .foregroundStyle(memoryPressureColor)
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
      Image(systemName: "display.2")
        .foregroundStyle(theme.color(for: .gpu))
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
    let cutoff = Date().addingTimeInterval(-30 * 60)
    let recent = coordinator.cpuHistory.filter { $0.timestamp >= cutoff }
    let points = HistoryChartSegmentation.points(from: recent)
    let color = theme.color(for: .cpu)
    return VStack(alignment: .leading, spacing: 4) {
      HStack {
        Label("CPU history", systemImage: "chart.xyaxis.line")
          .font(.caption.bold())
          .foregroundStyle(color)
        Spacer()
        Text(L10n.format("30 min · %g s", settings.samplingInterval))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Chart(points) { point in
        AreaMark(
          x: .value("Time", point.timestamp),
          y: .value("CPU", point.value),
          series: .value("Sampling epoch", point.segment))
          .foregroundStyle(
            LinearGradient(
              colors: [color.opacity(0.18), color.opacity(0.01)],
              startPoint: .top,
              endPoint: .bottom))
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value("CPU", point.value),
          series: .value("Sampling epoch", point.segment))
          .foregroundStyle(color)
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
      .frame(height: 100)
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
    case .normal: return "checkmark.circle.fill"
    default: return "questionmark.circle"
    }
  }

  private var memoryPressureColor: Color {
    switch coordinator.snapshot.memory.value?.pressureLevel {
    case .critical: return .red
    case .warning: return .orange
    case .normal: return theme.color(for: .memory)
    default: return theme.color(for: .neutral)
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

  private var batterySymbol: String {
    guard let battery = coordinator.snapshot.battery.value else { return "battery.0percent" }
    if battery.state == .charging { return "battery.100percent.bolt" }
    let percentage = battery.percentage ?? 0
    if percentage >= 75 { return "battery.100percent" }
    if percentage >= 40 { return "battery.50percent" }
    if percentage >= 15 { return "battery.25percent" }
    return "battery.0percent"
  }

  private var temperatureText: String {
    let stats = coordinator.snapshot.temperature.value
    let processor = MetricNumberFormatter.temperatureCelsius(stats?.processorCelsius)
    let battery = MetricNumberFormatter.temperatureCelsius(stats?.batteryCelsius)
    switch (processor, battery) {
    case (.some(let processor), .some(let battery)):
      return "\(processor) / \(battery)"
    case (.some(let processor), .none): return processor
    case (.none, .some(let battery)): return "🔋 \(battery)"
    case (.none, .none): return L10n.string("Collecting data")
    }
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
  @Environment(\.appTheme) private var theme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  let title: LocalizedStringKey
  let value: String
  let symbol: String
  let kind: MetricKind
  let action: () -> Void

  var body: some View {
    let color = theme.color(for: kind)
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: symbol)
          .font(.title3)
          .frame(width: 25)
          .foregroundStyle(color)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.caption).foregroundStyle(.secondary)
          Text(value)
            .font(.headline.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        Spacer(minLength: 4)
        Image(systemName: "chevron.right")
          .font(.caption.bold())
          .foregroundStyle(.tertiary)
      }
      .padding(10)
      .background(
        reduceTransparency
          ? Color(nsColor: .controlBackgroundColor)
          : color.opacity(theme.style == .multicolor ? 0.08 : 0.055),
        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .stroke(
            contrast == .increased ? color.opacity(0.65) : Color.secondary.opacity(0.16),
            lineWidth: contrast == .increased ? 1.5 : 1))
      .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityValue(value)
  }
}
