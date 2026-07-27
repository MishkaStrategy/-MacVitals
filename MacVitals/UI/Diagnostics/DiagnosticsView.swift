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
            ?? L10n.string("Unknown"))
        LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
      }

      Section("Providers") {
        row("CPU", snapshot.cpu.availability, snapshot.cpu.source, snapshot.cpu.timestamp)
        row(
          "Memory", snapshot.memory.availability, snapshot.memory.source,
          snapshot.memory.timestamp)
        row(
          "Battery", snapshot.battery.availability, snapshot.battery.source,
          snapshot.battery.timestamp,
          detail: BatteryDisplayText.summary(snapshot.battery))
        row(
          "Adapter", snapshot.adapter.availability, snapshot.adapter.source,
          snapshot.adapter.timestamp)
        row(
          "GPU", snapshot.gpu.value?.utilizationAvailability ?? .unsupported,
          snapshot.gpu.source, snapshot.gpu.timestamp)
        row(
          "Fans", snapshot.fans.availability, snapshot.fans.source,
          snapshot.fans.timestamp,
          detail: FanDisplayText.summary(snapshot.fans))
        row(
          "Power model", snapshot.power.availability, snapshot.power.source,
          snapshot.power.timestamp)
      }

      if let fans = snapshot.fans.value?.fans, !fans.isEmpty {
        Section("Fan details") {
          ForEach(fans) { fan in
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(L10n.format("Fan %d", fan.index + 1))
                Spacer()
                Text(MetricNumberFormatter.rpm(fan.currentRPM) ?? "—")
                  .monospacedDigit()
              }
              Text(FanDisplayText.detail(fan))
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(
                L10n.format(
                  "Range %@ – %@",
                  MetricNumberFormatter.rpm(fan.minimumRPM) ?? "—",
                  MetricNumberFormatter.rpm(fan.maximumRPM) ?? "—"))
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .accessibilityIdentifier("diagnosticsFan.\(fan.index)")
          }
        }
      }

      Section("Sampling") {
        if let health = samplingHealth {
          LabeledContent(
            "Total cycle",
            value: milliseconds(health.timings.totalMilliseconds))
          LabeledContent(
            "Configured interval",
            value: L10n.format("%.2f s", health.configuredIntervalSeconds))
          LabeledContent(
            "Cadence",
            value: L10n.string(health.overranInterval ? "Overrun" : "Within interval"))
          timingRow("CPU", health.timings.cpuMilliseconds)
          timingRow("Memory", health.timings.memoryMilliseconds)
          timingRow("Battery", health.timings.batteryMilliseconds)
          timingRow("Adapter", health.timings.adapterMilliseconds)
          timingRow("GPU", health.timings.gpuMilliseconds)
          timingRow("Fans", health.timings.fanMilliseconds)
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
      .accessibilityIdentifier("exportDiagnosticsButton")
    }
    .padding()
  }

  private func row(
    _ nameKey: String,
    _ availability: MetricAvailability,
    _ source: MetricSource,
    _ date: Date,
    detail: String? = nil
  ) -> some View {
    VStack(alignment: .leading) {
      HStack {
        Text(L10n.string(nameKey))
        Spacer()
        Text(availability.displayName).foregroundStyle(.secondary)
      }
      if let detail {
        Text(detail)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Text(
        L10n.format(
          "%@ · %@",
          source.displayName,
          date.formatted())
      )
      .font(.caption)
      .foregroundStyle(.tertiary)
    }
  }

  private func timingRow(_ nameKey: String, _ value: Double) -> some View {
    LabeledContent(L10n.string(nameKey), value: milliseconds(value))
  }

  private func milliseconds(_ value: Double) -> String {
    L10n.format("%.3f ms", value)
  }
}
