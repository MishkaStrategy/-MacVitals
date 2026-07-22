import SwiftUI

struct DiagnosticsView: View {
    let snapshot: SystemSnapshot
    var body: some View {
        List {
            Section("Application") { LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"); LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString) }
            Section("Providers") {
                row("CPU", snapshot.cpu.availability, snapshot.cpu.source, snapshot.cpu.timestamp)
                row("Memory", snapshot.memory.availability, snapshot.memory.source, snapshot.memory.timestamp)
                row("Battery", snapshot.battery.availability, snapshot.battery.source, snapshot.battery.timestamp)
                row("Adapter", snapshot.adapter.availability, snapshot.adapter.source, snapshot.adapter.timestamp)
                row("GPU", snapshot.gpu.value?.utilizationAvailability ?? .unsupported, snapshot.gpu.source, snapshot.gpu.timestamp)
                row("Power model", snapshot.power.availability, snapshot.power.source, snapshot.power.timestamp)
            }
            Button("Export redacted support bundle") { DiagnosticReportBuilder.export(snapshot: snapshot) }
        }.padding()
    }
    private func row(_ name: String, _ availability: MetricAvailability, _ source: MetricSource, _ date: Date) -> some View {
        VStack(alignment: .leading) { HStack { Text(name); Spacer(); Text(availability.rawValue).foregroundStyle(.secondary) }; Text("\(source.rawValue) · \(date.formatted())").font(.caption).foregroundStyle(.tertiary) }
    }
}
