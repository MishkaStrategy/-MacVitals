import Charts
import SwiftUI

nonisolated enum MetricDetailKind: String, Identifiable, Sendable {
  case cpu
  case memory
  case gpu
  case battery
  case fans

  var id: String { rawValue }

  var title: String {
    switch self {
    case .cpu: return L10n.string("CPU")
    case .memory: return L10n.string("Memory")
    case .gpu: return L10n.string("GPU")
    case .battery: return L10n.string("Battery")
    case .fans: return L10n.string("Fans")
    }
  }

  var symbol: String {
    switch self {
    case .cpu: return "cpu"
    case .memory: return "memorychip"
    case .gpu: return "rectangle.3.group"
    case .battery: return "battery.75percent"
    case .fans: return "fan"
    }
  }
}

private enum MetricHistoryRange: String, CaseIterable, Identifiable {
  case fiveMinutes
  case fifteenMinutes
  case oneHour

  var id: String { rawValue }

  var title: String {
    switch self {
    case .fiveMinutes: return "5 min"
    case .fifteenMinutes: return "15 min"
    case .oneHour: return "1 h"
    }
  }

  var sampleCount: Int {
    switch self {
    case .fiveMinutes: return 60
    case .fifteenMinutes: return 180
    case .oneHour: return 720
    }
  }

  var axisMinuteStride: Int {
    switch self {
    case .fiveMinutes: return 1
    case .fifteenMinutes: return 3
    case .oneHour: return 10
    }
  }
}

private struct FanHistoryChartPoint: Identifiable {
  let id: UUID
  let timestamp: Date
  let value: Double
  let fanIndex: Int
  let segment: Int

  var seriesKey: String { "fan-\(fanIndex)-segment-\(segment)" }
  var fanLabel: String { L10n.format("Fan %d", fanIndex + 1) }
}

struct MetricDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var fanControl: FanControlClient
  @State private var selectedRange: MetricHistoryRange = .fifteenMinutes

  let kind: MetricDetailKind

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      Divider()
      if kind == .fans {
        fanChart
        FanControlView(compact: true)
      } else {
        metricChart
      }
    }
    .padding(16)
    .frame(width: kind == .fans ? 600 : 560, height: kind == .fans ? 650 : 360)
    .onAppear {
      if kind == .fans { fanControl.refreshStatus() }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: kind.symbol)
        .font(.title2)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(kind.title).font(.headline)
        HStack(spacing: 6) {
          Text(currentValue)
            .font(.title3.monospacedDigit().bold())
          Text("· 5 s samples")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 12)
      Picker("Range", selection: $selectedRange) {
        ForEach(MetricHistoryRange.allCases) { range in
          Text(range.title).tag(range)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 190)
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.cancelAction)
      .help("Close")
      .accessibilityLabel("Close")
    }
  }

  @ViewBuilder
  private var metricChart: some View {
    let points = HistoryChartSegmentation.points(from: metricHistory)
    if points.isEmpty {
      unavailableChart
    } else {
      Chart(points) { point in
        AreaMark(
          x: .value("Time", point.timestamp),
          y: .value(kind.title, point.value),
          series: .value("Sampling epoch", point.segment)
        )
        .foregroundStyle(
          LinearGradient(
            colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom))
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value(kind.title, point.value),
          series: .value("Sampling epoch", point.segment)
        )
        .foregroundStyle(Color.accentColor)
        .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
      }
      .chartYScale(domain: 0...100)
      .chartXAxis { chartXAxis }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 5))
      }
      .chartPlotStyle { plotArea in
        plotArea
          .background(.quaternary.opacity(0.18))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .accessibilityLabel(kind.title)
    }
  }

  @ViewBuilder
  private var fanChart: some View {
    if fanPoints.isEmpty {
      unavailableChart
        .frame(height: 130)
    } else {
      Chart(fanPoints) { point in
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value("RPM", point.value),
          series: .value("Sampling epoch", point.seriesKey)
        )
        .foregroundStyle(by: .value("Fans", point.fanLabel))
        .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
      }
      .chartYScale(domain: fanYDomain)
      .chartXAxis { chartXAxis }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
      }
      .chartLegend(position: .bottom, alignment: .leading, spacing: 8)
      .chartPlotStyle { plotArea in
        plotArea
          .background(.quaternary.opacity(0.18))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .frame(height: 145)
      .accessibilityLabel(L10n.string("Fans"))
    }
  }

  private var unavailableChart: some View {
    VStack(spacing: 8) {
      Image(systemName: "chart.xyaxis.line")
        .font(.title)
        .foregroundStyle(.secondary)
      Text("Collecting data")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @AxisContentBuilder
  private var chartXAxis: some AxisContent {
    AxisMarks(values: .stride(by: .minute, count: selectedRange.axisMinuteStride)) { value in
      AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
      AxisTick()
      AxisValueLabel(format: .dateTime.hour().minute())
    }
  }

  private var metricHistory: [TimedPoint] {
    let history: [TimedPoint]
    switch kind {
    case .cpu: history = coordinator.cpuHistory
    case .memory: history = coordinator.memoryHistory
    case .gpu: history = coordinator.gpuHistory
    case .battery: history = coordinator.batteryHistory
    case .fans: history = []
    }
    return Array(history.suffix(selectedRange.sampleCount))
  }

  private var fanPoints: [FanHistoryChartPoint] {
    coordinator.fanHistory
      .sorted { $0.key < $1.key }
      .flatMap { index, history in
        HistoryChartSegmentation.points(
          from: Array(history.suffix(selectedRange.sampleCount)))
          .map { point in
            FanHistoryChartPoint(
              id: point.id,
              timestamp: point.timestamp,
              value: point.value,
              fanIndex: index,
              segment: point.segment)
          }
      }
  }

  private var fanYDomain: ClosedRange<Double> {
    let values = fanPoints.map(\.value)
    guard let minimum = values.min(), let maximum = values.max() else { return 0...8_000 }
    let lower = max(0, floor((minimum - 500) / 500) * 500)
    let upper = max(lower + 1_000, ceil((maximum + 500) / 500) * 500)
    return lower...upper
  }

  private var currentValue: String {
    switch kind {
    case .cpu:
      return MetricNumberFormatter.percentage(coordinator.snapshot.cpu.value?.total)
    case .memory:
      return MetricNumberFormatter.percentage(coordinator.snapshot.memory.value?.usedPercent)
    case .gpu:
      return MetricNumberFormatter.percentage(
        coordinator.snapshot.gpu.value?.systemUtilizationPercent)
    case .battery:
      return BatteryDisplayText.summary(coordinator.snapshot.battery)
    case .fans:
      return FanDisplayText.summary(coordinator.snapshot.fans)
    }
  }
}
