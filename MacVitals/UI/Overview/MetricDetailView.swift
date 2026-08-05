import Charts
import SwiftUI

nonisolated enum MetricDetailKind: String, Identifiable, Sendable {
  case cpu
  case memory
  case gpu
  case battery
  case temperature
  case fans
  case power

  var id: String { rawValue }

  var title: String {
    switch self {
    case .cpu: return L10n.string("CPU")
    case .memory: return L10n.string("Memory")
    case .gpu: return L10n.string("GPU")
    case .battery: return L10n.string("Battery")
    case .temperature: return TemperatureL10n.string("Temperature")
    case .fans: return L10n.string("Fans")
    case .power: return L10n.string("Power flow")
    }
  }

  var symbol: String {
    switch self {
    case .cpu: return "cpu"
    case .memory: return "memorychip"
    case .gpu: return "rectangle.3.group"
    case .battery: return "battery.75percent"
    case .temperature: return "thermometer.high"
    case .fans: return "fan.fill"
    case .power: return "bolt.horizontal.circle.fill"
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

  var duration: TimeInterval {
    switch self {
    case .fiveMinutes: return 5 * 60
    case .fifteenMinutes: return 15 * 60
    case .oneHour: return 60 * 60
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

struct MetricDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var settings: SettingsStore
  @EnvironmentObject private var fanControl: FanControlClient
  @State private var selectedRange: MetricHistoryRange = .fifteenMinutes
  @State private var selectedTemperatureSensorID: String?
  @StateObject private var processMonitor = ProcessConsumersMonitor()

  let kind: MetricDetailKind

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      Divider()
      switch kind {
      case .fans:
        fanChart
        FanControlView(compact: true)
      case .temperature:
        temperatureDetail
      case .power:
        powerDetail
      default:
        let chartModel = metricChartModel
        metricChart(
          points: chartModel.points,
          title: kind.title,
          yDomain: chartModel.yDomain)
          .frame(height: 205)
        if kind == .battery { batteryBreakdown }
        if let processMetric {
          ProcessConsumersView(monitor: processMonitor, metric: processMetric)
        }
      }
    }
    .padding(16)
    .frame(width: detailWidth, height: detailHeight)
    .onAppear {
      if kind == .fans { fanControl.refreshStatus() }
      if kind == .temperature { chooseInitialTemperatureSensor() }
      if processMetric != nil { processMonitor.start(interval: settings.samplingInterval) }
    }
    .onDisappear { processMonitor.stop() }
    .onChange(of: settings.samplingInterval) { interval in
      if processMetric != nil { processMonitor.restart(interval: interval) }
    }
    .onChange(of: coordinator.snapshot.temperature.value?.sensors.map(\.id) ?? []) { _ in
      if kind == .temperature { chooseInitialTemperatureSensor() }
    }
  }

  private var detailWidth: CGFloat {
    switch kind {
    case .fans, .temperature, .power: return 640
    case .cpu, .memory, .gpu, .battery: return 700
    }
  }

  private var detailHeight: CGFloat {
    switch kind {
    case .fans: return 650
    case .temperature: return 660
    case .power: return 520
    case .battery: return 780
    case .cpu, .memory, .gpu: return 610
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: kind.symbol)
        .font(.title2)
        .foregroundStyle(Color.accentColor)
        .frame(width: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text(kind.title).font(.headline)
        HStack(spacing: 6) {
          Text(currentValue)
            .font(.title3.monospacedDigit().bold())
          Text("·")
            .foregroundStyle(.tertiary)
          Text(L10n.format("Every %g s", settings.samplingInterval))
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
  private func metricChart(
    points: [HistoryChartPoint],
    title: String,
    yDomain: ClosedRange<Double>
  ) -> some View {
    if points.isEmpty {
      unavailableChart
    } else {
      Chart(points) { point in
        AreaMark(
          x: .value("Time", point.timestamp),
          y: .value(title, point.value),
          series: .value("Sampling epoch", point.segment)
        )
        .foregroundStyle(
          LinearGradient(
            colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom))
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value(title, point.value),
          series: .value("Sampling epoch", point.segment)
        )
        .foregroundStyle(Color.accentColor)
        .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
      }
      .chartYScale(domain: yDomain)
      .chartXAxis { chartXAxis }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 5))
      }
      .chartPlotStyle { plotArea in
        plotArea
          .background(.quaternary.opacity(0.18))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .accessibilityLabel(title)
    }
  }

  private var temperatureDetail: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(TemperatureL10n.string("Sensor history"), systemImage: "chart.xyaxis.line")
          .font(.subheadline.bold())
        Spacer()
        if !temperatureSensors.isEmpty {
          Picker(
            TemperatureL10n.string("Temperature sensor"),
            selection: Binding(
              get: { selectedTemperatureSensorID ?? temperatureSensors.first?.id },
              set: { selectedTemperatureSensorID = $0 })
          ) {
            ForEach(temperatureSensors) { sensor in
              Text(sensorPickerTitle(sensor)).tag(Optional(sensor.id))
            }
          }
          .labelsHidden()
          .frame(width: 260)
        }
      }

      let chartModel = selectedTemperatureChartModel
      metricChart(
        points: chartModel.points,
        title: selectedTemperatureSensor?.name ?? kind.title,
        yDomain: chartModel.yDomain)
        .frame(height: 210)

      HStack {
        Text(TemperatureL10n.string("Available sensors"))
          .font(.subheadline.bold())
        Spacer()
        Text(L10n.format("%d sensors", temperatureSensors.count))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      ScrollView {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 9) {
          ForEach(temperatureSensors) { sensor in
            temperatureSensorCard(sensor)
          }
        }
        .padding(.vertical, 1)
      }
    }
  }

  private func temperatureSensorCard(_ sensor: TemperatureReading) -> some View {
    Button {
      selectedTemperatureSensorID = sensor.id
    } label: {
      HStack(spacing: 10) {
        Image(systemName: sensor.category.symbolName)
          .font(.title3)
          .foregroundStyle(sensor.id == selectedTemperatureSensorID ? Color.accentColor : .secondary)
          .frame(width: 26)
        VStack(alignment: .leading, spacing: 2) {
          Text(sensor.name)
            .font(.caption.bold())
            .lineLimit(1)
          HStack(spacing: 5) {
            Text(sensor.category.displayName)
            if let key = sensor.key {
              Text("· \(key)")
                .monospaced()
            }
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
        Spacer()
        Text(L10n.format("%.1f °C", sensor.celsius))
          .font(.headline.monospacedDigit())
      }
      .padding(10)
      .background(
        sensor.id == selectedTemperatureSensorID
          ? Color.accentColor.opacity(0.12)
          : Color.secondary.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 10))
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(
            sensor.id == selectedTemperatureSensorID
              ? Color.accentColor.opacity(0.45)
              : Color.secondary.opacity(0.12),
            lineWidth: 1))
    }
    .buttonStyle(.plain)
  }

  private var powerDetail: some View {
    VStack(alignment: .leading, spacing: 12) {
      powerChart
        .frame(height: 250)
      HStack(spacing: 10) {
        detailValueCard(
          title: L10n.string("System consumption"),
          value: MetricNumberFormatter.decimalWatts(
            coordinator.snapshot.power.value?.estimatedSystemPowerWatts,
            estimated: coordinator.snapshot.power.isEstimated)
            ?? L10n.string("Collecting data"),
          detail: coordinator.snapshot.power.isEstimated
            ? L10n.string("Calculated") : L10n.string("Direct telemetry"),
          symbol: "laptopcomputer")
        detailValueCard(
          title: L10n.string("Battery flow"),
          value: MetricNumberFormatter.decimalWatts(currentBatteryPower, absolute: true)
            ?? L10n.string("Collecting data"),
          detail: BatteryPowerFlowState.resolve(currentBatteryPower).displayName,
          symbol: "battery.75percent")
        detailValueCard(
          title: L10n.string("Adapter input"),
          value: MetricNumberFormatter.decimalWatts(
            coordinator.snapshot.power.value?.adapterInputPowerWatts)
            ?? L10n.string("Not measured"),
          detail: MetricNumberFormatter.ratedWatts(
            coordinator.snapshot.adapter.value?.ratedPowerWatts)
            ?? L10n.string("Adapter rating unavailable"),
          symbol: "powerplug.fill")
      }
    }
  }

  @ViewBuilder
  private var powerChart: some View {
    let model = powerChartModel
    if model.points.isEmpty {
      unavailableChart
    } else {
      Chart(model.points) { point in
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value("W", point.value),
          series: .value("Series", point.seriesKey))
          .foregroundStyle(by: .value("Power", point.series))
          .lineStyle(StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        RuleMark(y: .value("Zero", 0))
          .foregroundStyle(.secondary.opacity(0.35))
      }
      .chartYScale(domain: model.yDomain)
      .chartXAxis { chartXAxis }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 5))
      }
      .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
      .chartPlotStyle { plotArea in
        plotArea
          .background(.quaternary.opacity(0.18))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .accessibilityLabel(L10n.string("Power flow"))
    }
  }

  private var batteryBreakdown: some View {
    let battery = coordinator.snapshot.battery.value
    return VStack(alignment: .leading, spacing: 10) {
      Text(L10n.string("Battery details"))
        .font(.subheadline.bold())
      LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 9) {
        detailValueCard(
          title: TemperatureL10n.string("Battery temperature"),
          value: MetricNumberFormatter.temperatureCelsius(battery?.temperatureCelsius)
            ?? L10n.string("Collecting data"),
          detail: TemperatureL10n.string("Direct battery sensor"),
          symbol: "thermometer.medium")
        detailValueCard(
          title: L10n.string("Battery flow"),
          value: MetricNumberFormatter.decimalWatts(currentBatteryPower, absolute: true)
            ?? L10n.string("Collecting data"),
          detail: BatteryPowerFlowState.resolve(currentBatteryPower).displayName,
          symbol: "bolt.fill")
        detailValueCard(
          title: L10n.string("Battery health"),
          value: MetricNumberFormatter.percentage(battery?.healthPercent),
          detail: battery?.cycleCount.map { L10n.format("%d cycles", $0) }
            ?? L10n.string("Cycle count unavailable"),
          symbol: "heart.text.square.fill")
        detailValueCard(
          title: L10n.string("Voltage"),
          value: battery?.voltageVolts.map { L10n.format("%.2f V", $0) }
            ?? L10n.string("Collecting data"),
          detail: L10n.string("Battery voltage"),
          symbol: "waveform.path.ecg")
        detailValueCard(
          title: L10n.string("Current"),
          value: battery?.currentAmperes.map { L10n.format("%.2f A", $0) }
            ?? L10n.string("Collecting data"),
          detail: L10n.string("Signed current"),
          symbol: "arrow.left.arrow.right")
        detailValueCard(
          title: L10n.string("Condition"),
          value: battery?.condition ?? L10n.string("Unknown"),
          detail: battery?.state.displayName ?? L10n.string("Unknown"),
          symbol: "checkmark.shield.fill")
      }
    }
  }

  private func detailValueCard(
    title: String,
    value: String,
    detail: String,
    symbol: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(title, systemImage: symbol)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.headline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text(detail)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .padding(10)
    .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
  }

  @ViewBuilder
  private var fanChart: some View {
    let model = fanChartModel
    if model.points.isEmpty {
      unavailableChart
        .frame(height: 130)
    } else {
      Chart(model.points) { point in
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value("RPM", point.value),
          series: .value("Sampling epoch", point.seriesKey)
        )
        .foregroundStyle(by: .value("Fans", point.fanLabel))
        .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
      }
      .chartYScale(domain: model.yDomain)
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

  private var processMetric: ProcessConsumerMetric? {
    switch kind {
    case .cpu: return .cpu
    case .memory: return .memory
    case .gpu: return .gpu
    case .battery: return .energy
    case .temperature, .fans, .power: return nil
    }
  }

  private var metricChartModel: ScalarHistoryChartModel {
    MetricHistoryChartModelBuilder.scalar(
      history: metricSourceHistory,
      cutoff: historyCutoff,
      yDomain: 0...100)
  }

  private var metricSourceHistory: [TimedPoint] {
    switch kind {
    case .cpu: return coordinator.cpuHistory
    case .memory: return coordinator.memoryHistory
    case .gpu: return coordinator.gpuHistory
    case .battery: return coordinator.batteryHistory
    case .temperature: return selectedTemperatureHistory
    case .fans, .power: return []
    }
  }

  private var temperatureSensors: [TemperatureReading] {
    coordinator.snapshot.temperature.value?.sensors ?? []
  }

  private var selectedTemperatureSensor: TemperatureReading? {
    if let selectedTemperatureSensorID,
      let selected = temperatureSensors.first(where: { $0.id == selectedTemperatureSensorID })
    {
      return selected
    }
    return temperatureSensors.first(where: { $0.isPrimary }) ?? temperatureSensors.first
  }

  private var selectedTemperatureHistory: [TimedPoint] {
    guard let id = selectedTemperatureSensor?.id else { return coordinator.temperatureHistory }
    return coordinator.temperatureSensorHistory[id] ?? []
  }

  private func chooseInitialTemperatureSensor() {
    guard !temperatureSensors.isEmpty else {
      selectedTemperatureSensorID = nil
      return
    }
    if let id = selectedTemperatureSensorID, temperatureSensors.contains(where: { $0.id == id }) {
      return
    }
    selectedTemperatureSensorID = temperatureSensors.first(where: { $0.isPrimary })?.id
      ?? temperatureSensors.first?.id
  }

  private func sensorPickerTitle(_ sensor: TemperatureReading) -> String {
    if let key = sensor.key { return "\(sensor.name) · \(key)" }
    return sensor.name
  }

  private var selectedTemperatureChartModel: ScalarHistoryChartModel {
    MetricHistoryChartModelBuilder.temperature(
      history: selectedTemperatureHistory,
      cutoff: historyCutoff)
  }

  private var fanChartModel: FanHistoryChartModel {
    MetricHistoryChartModelBuilder.fans(
      histories: coordinator.fanHistory,
      cutoff: historyCutoff)
  }

  private var powerChartModel: PowerHistoryChartModel {
    MetricHistoryChartModelBuilder.power(
      series: [
        PowerHistorySeries(
          name: L10n.string("System consumption"),
          history: coordinator.systemPowerHistory),
        PowerHistorySeries(
          name: L10n.string("Battery flow"),
          history: coordinator.batteryPowerHistory),
        PowerHistorySeries(
          name: L10n.string("Adapter input"),
          history: coordinator.adapterInputPowerHistory),
      ],
      cutoff: historyCutoff)
  }

  private var historyCutoff: Date {
    Date().addingTimeInterval(-selectedRange.duration)
  }

  private var currentBatteryPower: Double? {
    coordinator.snapshot.power.value?.batteryPowerWatts
      ?? coordinator.snapshot.battery.value?.batteryPowerWatts
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
    case .temperature:
      let processor = MetricNumberFormatter.temperatureCelsius(
        coordinator.snapshot.temperature.value?.processorCelsius)
      let battery = MetricNumberFormatter.temperatureCelsius(
        coordinator.snapshot.temperature.value?.batteryCelsius)
      return [processor, battery].compactMap { $0 }.joined(separator: " / ").nilIfEmpty
        ?? L10n.string("Collecting data")
    case .fans:
      return FanDisplayText.summary(coordinator.snapshot.fans)
    case .power:
      return MetricNumberFormatter.decimalWatts(
        coordinator.snapshot.power.value?.estimatedSystemPowerWatts,
        estimated: coordinator.snapshot.power.isEstimated)
        ?? L10n.string("Collecting data")
    }
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension BatteryState {
  var displayName: String {
    switch self {
    case .charging: return L10n.string("Charging")
    case .discharging: return L10n.string("Discharging")
    case .charged: return L10n.string("Charged")
    case .paused: return L10n.string("Charging paused")
    case .adapterPower: return L10n.string("Adapter power")
    case .unknown: return L10n.string("Unknown")
    case .absent: return L10n.string("No battery")
    }
  }
}
