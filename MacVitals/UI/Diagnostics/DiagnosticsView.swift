import SwiftUI

struct DiagnosticsView: View {
  let snapshot: SystemSnapshot
  let samplingHealth: SamplingHealth?

  var body: some View {
    List {
      Section("Application") {
        LabeledContent(
          "Version",
          value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "Unknown")
        LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
      }

      Section("Providers") {
        row("CPU", snapshot.cpu.availability, snapshot.cpu.source, snapshot.cpu.timestamp)
        row(
          "Memory", snapshot.memory.availability, snapshot.memory.source,
          snapshot.memory.timestamp)
        row(
          "Battery", snapshot.battery.availability, snapshot.battery.source,
          snapshot.battery.timestamp)
        row(
          "Adapter", snapshot.adapter.availability, snapshot.adapter.source,
          snapshot.adapter.timestamp)
        row(
          "GPU", snapshot.gpu.value?.utilizationAvailability ?? .unsupported,
          snapshot.gpu.source, snapshot.gpu.timestamp)
        row(
          "Power model", snapshot.power.availability, snapshot.power.source,
          snapshot.power.timestamp)
      }

      Section("Sampling") {
        if let health = samplingHealth {
          LabeledContent(
            "Total cycle",
            value: milliseconds(health.timings.totalMilliseconds))
          LabeledContent(
            "Configured interval",
            value: String(format: "%.2f s", health.configuredIntervalSeconds))
          LabeledContent(
            "Cadence",
            value: health.overranInterval ? "Overrun" : "Within interval")
          timingRow("CPU", health.timings.cpuMilliseconds)
          timingRow("Memory", health.timings.memoryMilliseconds)
          timingRow("Battery", health.timings.batteryMilliseconds)
          timingRow("Adapter", health.timings.adapterMilliseconds)
          timingRow("GPU", health.timings.gpuMilliseconds)
          timingRow("Power model", health.timings.powerModelMilliseconds)
        } else {
          Text("Waiting for the first sampling cycle")
            .foregroundStyle(.secondary)
        }
      }

      Button("Export redacted support bundle") {
        DiagnosticReportBuilder.export(
          snapshot: snapshot,
          samplingHealth: samplingHealth)
      }
    }
    .padding()
  }

  private func row(
    _ name: String,
    _ availability: MetricAvailability,
    _ source: MetricSource,
    _ date: Date
  ) -> some View {
    VStack(alignment: .leading) {
      HStack {
        Text(name)
        Spacer()
        Text(availability.rawValue).foregroundStyle(.secondary)
      }
      Text("\(source.rawValue) · \(date.formatted())")
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
  }

  private func timingRow(_ name: String, _ value: Double) -> some View {
    LabeledContent(name, value: milliseconds(value))
  }

  private func milliseconds(_ value: Double) -> String {
    String(format: "%.3f ms", value)
  }
}
