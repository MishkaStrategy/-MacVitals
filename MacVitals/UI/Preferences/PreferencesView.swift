import SwiftUI

struct PreferencesView: View {
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    TabView {
      generalTab
        .tabItem { Label("General", systemImage: "gear") }

      alertsTab
        .tabItem { Label("Alerts", systemImage: "bell") }

      menuBarTab
        .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

      DiagnosticsView(
        snapshot: coordinator.snapshot,
        samplingHealth: coordinator.samplingHealth
      )
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

      VStack(alignment: .leading, spacing: 4) {
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { settings.launchAtLogin },
            set: { enabled in settings.setLaunchAtLogin(enabled) }
          )
        )
        .accessibilityIdentifier("launchAtLoginToggle")

        if let message = settings.launchAtLoginState.message {
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("launchAtLoginStatusMessage")
        }
      }

      Toggle("Reduce motion", isOn: $settings.reducedMotion)
        .accessibilityIdentifier("reduceMotionToggle")
    }
    .padding()
  }

  private var alertsTab: some View {
    Form {
      Toggle("Enable local alerts", isOn: $settings.notificationsEnabled)
        .accessibilityIdentifier("notificationsEnabledToggle")

      if settings.notificationsEnabled,
        let message = settings.notificationAuthorizationState.message
      {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("notificationAuthorizationStatusMessage")
      }

      LabeledContent("Memory threshold") {
        HStack {
          Slider(value: $settings.memoryAlertThreshold, in: 50...100, step: 5)
            .accessibilityIdentifier("memoryAlertThresholdSlider")
            .frame(width: 220)
          Text("\(Int(settings.memoryAlertThreshold))%")
            .monospacedDigit()
            .frame(width: 42, alignment: .trailing)
        }
      }
      .disabled(!settings.notificationsEnabled)

      LabeledContent("Low battery threshold") {
        HStack {
          Slider(value: $settings.lowBatteryAlertThreshold, in: 5...50, step: 5)
            .accessibilityIdentifier("lowBatteryAlertThresholdSlider")
            .frame(width: 220)
          Text("\(Int(settings.lowBatteryAlertThreshold))%")
            .monospacedDigit()
            .frame(width: 42, alignment: .trailing)
        }
      }
      .disabled(!settings.notificationsEnabled)

      Text(
        "Alerts are generated only on state transitions and use a cooldown to prevent repeated notifications. System permission is requested only when local alerts are enabled. Native macOS memory pressure can trigger an alert before the percentage threshold is reached."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding()
  }

  private var menuBarTab: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Preset", selection: $settings.selectedPreset) {
        ForEach(MenuPreset.allCases) { preset in
          Text(preset.displayName).tag(preset)
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
              .help(L10n.string("Hide metric"))
              .accessibilityLabel(L10n.format("Hide %@", metric.displayName))
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
              .accessibilityLabel(L10n.format("Show %@", metric.displayName))
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
      .accessibilityIdentifier("privacyLocalOnlySummary")
      Text(
        "The support bundle redacts home paths and does not include serial numbers, Apple ID, user documents, network data, or stable GPU registry identifiers."
      )
      .accessibilityIdentifier("privacySupportBundleSummary")
      Spacer()
    }
    .padding()
  }
}
