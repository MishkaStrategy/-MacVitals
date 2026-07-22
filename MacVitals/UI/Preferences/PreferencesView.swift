import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var coordinator: MetricsCoordinator
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        TabView {
            Form {
                Picker("Update interval", selection: $settings.samplingInterval) {
                    ForEach([0.5, 1, 2, 5, 10], id: \.self) { Text("\($0, specifier: "%g") s").tag($0) }
                }
                Toggle("Show in Dock", isOn: $settings.showInDock)
                Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
                Toggle("Reduce motion", isOn: $settings.reducedMotion)
            }.padding().tabItem { Label("General", systemImage: "gear") }

            VStack(alignment: .leading) {
                Picker("Preset", selection: $settings.selectedPreset) { ForEach(MenuPreset.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                List {
                    ForEach(settings.enabledMetrics) { metric in Label(metric.rawValue.capitalized, systemImage: metric.defaultSymbol) }
                        .onMove(perform: settings.move)
                }
                Text("Drag metrics to change their order. Separate status items remain experimental and are not enabled in v1.0.0.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack { Spacer(); Button("Restore Defaults") { settings.reset() } }
            }.padding().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

            DiagnosticsView(snapshot: coordinator.snapshot)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }

            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy").font(.title2.bold())
                Text("MacVitals has no accounts, telemetry, analytics, ads, or network backend. Measurements and preferences remain on this Mac.")
                Text("The support bundle redacts home paths and does not include serial numbers, Apple ID, user documents, or network data.")
                Spacer()
            }.padding().tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(minWidth: 620, minHeight: 520)
    }
}
