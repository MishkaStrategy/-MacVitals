import SwiftUI

struct PreferencesView: View {
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    TabView {
      generalTab
        .tabItem { Label("General", systemImage: "gear") }

      menuBarTab
        .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

      DiagnosticsView(snapshot: coordinator.snapshot)
        .tabItem { Label("Diagnostics", systemImage: "stethoscope") }

      privacyTab
        .tabItem { Label("Privacy", systemImage: "hand.raised") }
    }
    .frame(minWidth: 620, minHeight: 520)
  }

  private var generalTab: some View {
    Form {
      Picker("Update interval", selection: $settings.samplingInterval) {
        ForEach([0.5, 1, 2, 5, 10], id: \.self) {
          Text("\($0, specifier: "%g") s").tag($0)
        }
      }
      .accessibilityIdentifier("samplingIntervalPicker")

      Toggle("Show in Dock", isOn: $settings.showInDock)
        .accessibilityIdentifier("showInDockToggle")

      Toggle(
        "Launch at login",
        isOn: Binding(
          get: { settings.launchAtLogin },
          set: { enabled in settings.setLaunchAtLogin(enabled) }
        )
      )
      .accessibilityIdentifier("launchAtLoginToggle")

      Toggle("Reduce motion", isOn: $settings.reducedMotion)
        .accessibilityIdentifier("reduceMotionToggle")
    }
    .padding()
  }

  private var menuBarTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Preset", selection: $settings.selectedPreset) {
        ForEach(MenuPreset.allCases) { preset in
          Text(preset.rawValue.capitalized).tag(preset)
        }
      }
      .accessibilityIdentifier("menuPresetPicker")

      List {
        Section("Shown in menu bar") {
          ForEach(settings.enabledMetrics) { metric in
            HStack {
              Label(metric.displayName, systemImage: metric.defaultSymbol)
              Spacer()
              Button {
                settings.setMetric(metric, enabled: false)
              } label: {
                Image(systemName: "eye.slash")
              }
              .buttonStyle(.borderless)
              .help("Hide metric")
              .accessibilityLabel("Hide \(metric.displayName)")
              .accessibilityIdentifier("hideMetric.\(metric.rawValue)")
            }
            .accessibilityIdentifier("shownMetric.\(metric.rawValue)")
          }
          .onMove(perform: settings.move)
        }

        if !settings.hiddenMetrics.isEmpty {
          Section("Hidden metrics") {
            ForEach(settings.hiddenMetrics) { metric in
              Button {
                settings.setMetric(metric, enabled: true)
              } label: {
                HStack {
                  Label(metric.displayName, systemImage: metric.defaultSymbol)
                  Spacer()
                  Image(systemName: "plus.circle")
                }
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Show \(metric.displayName)")
              .accessibilityIdentifier("showMetric.\(metric.rawValue)")
            }
          }
        }
      }
      .accessibilityIdentifier("menuMetricLayoutList")

      Text(
        "Drag shown metrics to change their order. Hide a metric with the eye button or restore it from the hidden section. Separate status items remain experimental and are not enabled in v1.0.0."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack {
        Spacer()
        Button("Restore Defaults") { settings.reset() }
          .accessibilityIdentifier("restoreDefaultsButton")
      }
    }
    .padding()
  }

  private var privacyTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Privacy").font(.title2.bold())
      Text(
        "MacVitals has no accounts, telemetry, analytics, ads, or network backend. Measurements and preferences remain on this Mac."
      )
      Text(
        "The support bundle redacts home paths and does not include serial numbers, Apple ID, user documents, or network data."
      )
      Spacer()
    }
    .padding()
  }
}
