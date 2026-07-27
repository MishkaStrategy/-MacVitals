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
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var fanControl: FanControlClient

  let kind: MetricDetailKind

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      if kind == .fans {
        fanChart
        Divider()
        FanControlView()
      } else {
        metricChart
      }
    }
    .padding(18)
    .frame(width: 720, height: kind == .fans ? 700 : 460)
    .onAppear {
      if kind == .fans { fanControl.refreshStatus() }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: kind.symbol)
        .font(.title2)
        .frame(width: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text(kind.title).font(.title2.bold())
        Text(currentValue)
          .font(.title3.monospacedDigit())
        Text("1 h · 5 s")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
  }

  @ViewBuilder
  private var metricChart: some View {
    let points = HistoryChartSegmentation.points(from: metricHistory)
    if points.isEmpty {
      unavailableChart
    } else {
      Chart(points) { point in
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value(kind.title, point.value),
          series: .value("Sampling epoch", point.segment)
        )
        .foregroundStyle(Color.accentColor)
      }
      .chartYScale(domain: 0...100)
      .chartXAxis { chartXAxis }
      .chartYAxis {
        AxisMarks(position: .leading)
      }
      .accessibilityLabel(kind.title)
    }
  }

  @ViewBuilder
  private var fanChart: some View {
    if fanPoints.isEmpty {
      unavailableChart
        .frame(height: 180)
    } else {
      Chart(fanPoints) { point in
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value("RPM", point.value),
          series: .value("Sampling epoch", point.seriesKey)
        )
        .foregroundStyle(by: .value("Fans", point.fanLabel))
      }
      .chartYScale(domain: fanYDomain)
      .chartXAxis { chartXAxis }
      .chartYAxis {
        AxisMarks(position: .leading)
      }
      .chartLegend(position: .bottom, alignment: .leading)
      .frame(height: 210)
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
    AxisMarks(values: .stride(by: .second, count: 5)) {
      AxisTick()
    }
    AxisMarks(values: .stride(by: .minute, count: 5)) { value in
      AxisGridLine()
      AxisValueLabel(format: .dateTime.hour().minute())
    }
  }

  private var metricHistory: [TimedPoint] {
    switch kind {
    case .cpu: return coordinator.cpuHistory
    case .memory: return coordinator.memoryHistory
    case .gpu: return coordinator.gpuHistory
    case .battery: return coordinator.batteryHistory
    case .fans: return []
    }
  }

  private var fanPoints: [FanHistoryChartPoint] {
    coordinator.fanHistory
      .sorted { $0.key < $1.key }
      .flatMap { index, history in
        HistoryChartSegmentation.points(from: history).map { point in
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
