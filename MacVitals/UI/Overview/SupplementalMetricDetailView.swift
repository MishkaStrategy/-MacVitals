import AppKit
import Charts
import SwiftUI

nonisolated enum SupplementalMetricDetailKind: String, Identifiable, Sendable {
  case network
  case storage

  var id: String { rawValue }

  var title: String {
    switch self {
    case .network: return NetworkL10n.string("Network")
    case .storage: return StorageL10n.string("Storage")
    }
  }

  var symbol: String {
    switch self {
    case .network: return "network"
    case .storage: return "internaldrive.fill"
    }
  }

  var themeMetricKind: MetricKind {
    switch self {
    case .network: return .fans
    case .storage: return .memory
    }
  }
}

private enum SupplementalHistoryRange: String, CaseIterable, Identifiable {
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

private struct NetworkDetailChartPoint: Identifiable {
  let id = UUID()
  let timestamp: Date
  let value: Double
  let series: String
}

private struct StorageDetailChartPoint: Identifiable {
  let id = UUID()
  let timestamp: Date
  let value: Double
  let series: String
}

@MainActor
final class SupplementalMetricDetailWindowPresenter: NSObject, NSWindowDelegate {
  static let shared = SupplementalMetricDetailWindowPresenter()

  private var windowController: NSWindowController?

  func show(
    kind: SupplementalMetricDetailKind,
    settings: SettingsStore,
    networkMonitor: NetworkTrafficMonitor,
    storageMonitor: StorageUsageMonitor
  ) {
    let rootView = ThemedMetricDetailRoot(metric: kind.themeMetricKind) {
      SupplementalMetricDetailView(
        kind: kind,
        networkMonitor: networkMonitor,
        storageMonitor: storageMonitor)
        .environmentObject(settings)
    }

    let hostingController = NSHostingController(rootView: rootView)
    let size = NSSize(width: 720, height: kind == .network ? 650 : 610)

    if let window = windowController?.window {
      window.contentViewController = hostingController
      window.title = kind.title
      window.setContentSize(size)
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let window = NSWindow(contentViewController: hostingController)
    window.title = kind.title
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.setContentSize(size)
    window.minSize = NSSize(width: 620, height: 500)
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.delegate = self
    window.center()

    let controller = NSWindowController(window: window)
    windowController = controller
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    windowController = nil
  }
}

struct SupplementalMetricDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var settings: SettingsStore
  @ObservedObject private var networkMonitor: NetworkTrafficMonitor
  @ObservedObject private var storageMonitor: StorageUsageMonitor
  @State private var selectedRange: SupplementalHistoryRange = .fifteenMinutes

  let kind: SupplementalMetricDetailKind

  init(
    kind: SupplementalMetricDetailKind,
    networkMonitor: NetworkTrafficMonitor,
    storageMonitor: StorageUsageMonitor
  ) {
    self.kind = kind
    self.networkMonitor = networkMonitor
    self.storageMonitor = storageMonitor
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      Divider()
      switch kind {
      case .network: networkDetail
      case .storage: storageDetail
      }
    }
    .padding(16)
    .frame(width: 700, height: kind == .network ? 610 : 570)
    .onAppear {
      switch kind {
      case .network: networkMonitor.start(interval: settings.samplingInterval)
      case .storage: storageMonitor.start(interval: settings.samplingInterval)
      }
    }
    .onDisappear {
      switch kind {
      case .network: networkMonitor.stop()
      case .storage: storageMonitor.stop()
      }
    }
    .onChange(of: settings.samplingInterval) { interval in
      switch kind {
      case .network: networkMonitor.restart(interval: interval)
      case .storage: storageMonitor.restart(interval: interval)
      }
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
          Text("·").foregroundStyle(.tertiary)
          Text(L10n.format("Every %g s", settings.samplingInterval))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 12)
      Picker("Range", selection: $selectedRange) {
        ForEach(SupplementalHistoryRange.allCases) { range in
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

  private var currentValue: String {
    switch kind {
    case .network:
      return NetworkByteFormatter.rate(networkMonitor.snapshot?.downloadBytesPerSecond)
    case .storage:
      guard let snapshot = storageMonitor.snapshot else { return "—" }
      return StorageByteFormatter.percentage(snapshot.usedFraction)
    }
  }

  private var networkDetail: some View {
    VStack(alignment: .leading, spacing: 14) {
      networkChart
        .frame(height: 260)

      LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
        detailValueCard(
          title: NetworkL10n.string("Download"),
          value: NetworkByteFormatter.rate(networkMonitor.snapshot?.downloadBytesPerSecond),
          detail: NetworkL10n.string("Current speed"),
          symbol: "arrow.down")
        detailValueCard(
          title: NetworkL10n.string("Upload"),
          value: NetworkByteFormatter.rate(networkMonitor.snapshot?.uploadBytesPerSecond),
          detail: NetworkL10n.string("Current speed"),
          symbol: "arrow.up")
        detailValueCard(
          title: NetworkL10n.string("Received this session"),
          value: NetworkByteFormatter.bytes(networkMonitor.snapshot?.sessionReceivedBytes ?? 0),
          detail: NetworkL10n.string("Current session"),
          symbol: "tray.and.arrow.down.fill")
        detailValueCard(
          title: NetworkL10n.string("Sent this session"),
          value: NetworkByteFormatter.bytes(networkMonitor.snapshot?.sessionSentBytes ?? 0),
          detail: NetworkL10n.string("Current session"),
          symbol: "tray.and.arrow.up.fill")
      }

      if let snapshot = networkMonitor.snapshot {
        HStack {
          Label(NetworkL10n.string("Interface totals"), systemImage: "network")
            .font(.caption.bold())
          Spacer()
          Text(
            "\(snapshot.interfaceName) · \(NetworkL10n.string("Received")) "
              + "\(NetworkByteFormatter.bytes(snapshot.receivedBytes)) · "
              + "\(NetworkL10n.string("Sent")) \(NetworkByteFormatter.bytes(snapshot.sentBytes))"
          )
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private var networkChart: some View {
    let points = networkChartPoints
    if points.isEmpty {
      unavailableChart(NetworkL10n.string("Network data unavailable"))
    } else {
      Chart(points) { point in
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value("Bytes per second", point.value),
          series: .value("Direction", point.series))
          .foregroundStyle(by: .value("Direction", point.series))
          .lineStyle(StrokeStyle(lineWidth: 1.7, lineJoin: .round))
      }
      .chartXScale(domain: chartXDomain)
      .chartYScale(domain: 0...networkYMaximum)
      .chartXAxis { chartXAxis }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
          AxisTick()
          AxisValueLabel {
            if let rate = value.as(Double.self) {
              Text(NetworkByteFormatter.rate(rate))
            }
          }
        }
      }
      .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
      .chartPlotStyle { plotArea in
        plotArea
          .background(.quaternary.opacity(0.18))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .accessibilityLabel(NetworkL10n.string("Traffic history"))
    }
  }

  private var storageDetail: some View {
    VStack(alignment: .leading, spacing: 14) {
      storageChart
        .frame(height: 265)

      if let snapshot = storageMonitor.snapshot {
        ProgressView(value: snapshot.usedFraction)
          .tint(Color.accentColor)
          .accessibilityLabel(StorageL10n.string("Used"))
          .accessibilityValue(StorageByteFormatter.percentage(snapshot.usedFraction))

        LazyVGrid(columns: [.init(.flexible()), .init(.flexible()), .init(.flexible())], spacing: 10) {
          detailValueCard(
            title: StorageL10n.string("Used"),
            value: StorageByteFormatter.bytes(snapshot.usedBytes),
            detail: StorageByteFormatter.percentage(snapshot.usedFraction),
            symbol: "internaldrive.fill")
          detailValueCard(
            title: StorageL10n.string("Available"),
            value: StorageByteFormatter.bytes(snapshot.availableBytes),
            detail: snapshot.volumeName,
            symbol: "externaldrive.badge.checkmark")
          detailValueCard(
            title: StorageL10n.string("Total"),
            value: StorageByteFormatter.bytes(snapshot.totalBytes),
            detail: StorageL10n.string("Volume capacity"),
            symbol: "chart.pie.fill")
        }
      } else {
        unavailableChart(StorageL10n.string("Storage data unavailable"))
      }
    }
  }

  @ViewBuilder
  private var storageChart: some View {
    let points = storageChartPoints
    if points.isEmpty {
      unavailableChart(StorageL10n.string("Storage data unavailable"))
    } else {
      Chart(points) { point in
        LineMark(
          x: .value("Time", point.timestamp),
          y: .value("Bytes", point.value),
          series: .value("Storage", point.series))
          .foregroundStyle(by: .value("Storage", point.series))
          .lineStyle(StrokeStyle(lineWidth: 1.7, lineJoin: .round))
      }
      .chartXScale(domain: chartXDomain)
      .chartYScale(domain: 0...storageYMaximum)
      .chartXAxis { chartXAxis }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
          AxisTick()
          AxisValueLabel {
            if let bytes = value.as(Double.self) {
              Text(StorageByteFormatter.bytes(UInt64(max(0, bytes))))
            }
          }
        }
      }
      .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
      .chartPlotStyle { plotArea in
        plotArea
          .background(.quaternary.opacity(0.18))
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }
      .accessibilityLabel(StorageL10n.string("Storage history"))
    }
  }

  private var networkChartPoints: [NetworkDetailChartPoint] {
    let cutoff = Date().addingTimeInterval(-selectedRange.duration)
    return networkMonitor.history
      .filter { $0.timestamp >= cutoff }
      .flatMap { sample in
        [
          NetworkDetailChartPoint(
            timestamp: sample.timestamp,
            value: sample.downloadBytesPerSecond,
            series: NetworkL10n.string("Download")),
          NetworkDetailChartPoint(
            timestamp: sample.timestamp,
            value: sample.uploadBytesPerSecond,
            series: NetworkL10n.string("Upload")),
        ]
      }
  }

  private var storageChartPoints: [StorageDetailChartPoint] {
    let cutoff = Date().addingTimeInterval(-selectedRange.duration)
    return storageMonitor.history
      .filter { $0.timestamp >= cutoff }
      .flatMap { sample in
        [
          StorageDetailChartPoint(
            timestamp: sample.timestamp,
            value: Double(sample.usedBytes),
            series: StorageL10n.string("Used")),
          StorageDetailChartPoint(
            timestamp: sample.timestamp,
            value: Double(sample.availableBytes),
            series: StorageL10n.string("Available")),
        ]
      }
  }

  private var networkYMaximum: Double {
    max(1, (networkChartPoints.map(\.value).max() ?? 1) * 1.12)
  }

  private var storageYMaximum: Double {
    max(1, Double(storageMonitor.snapshot?.totalBytes ?? 1))
  }

  private var chartXDomain: ClosedRange<Date> {
    let end = Date()
    return end.addingTimeInterval(-selectedRange.duration)...end
  }

  private var chartXAxis: some AxisContent {
    AxisMarks(values: .stride(by: .minute, count: selectedRange.axisMinuteStride)) { value in
      AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
      AxisTick()
      AxisValueLabel(format: .dateTime.hour().minute())
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
        .font(.caption.bold())
        .foregroundStyle(Color.accentColor)
      Text(value)
        .font(.title3.monospacedDigit().bold())
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(detail)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.secondary.opacity(0.13), lineWidth: 1))
  }

  private func unavailableChart(_ message: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: "chart.xyaxis.line")
        .font(.system(size: 34, weight: .medium))
        .foregroundStyle(.secondary)
      Text(message)
        .font(.headline)
      Text(L10n.string("Collecting data"))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
  }
}
