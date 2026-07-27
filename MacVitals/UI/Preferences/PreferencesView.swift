import SwiftUI

private enum PreferencesSection: String, CaseIterable, Identifiable {
  case general
  case alerts
  case menuBar
  case fans
  case diagnostics
  case privacy

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return L10n.string("General")
    case .alerts: return L10n.string("Alerts")
    case .menuBar: return L10n.string("Menu Bar")
    case .fans: return L10n.string("Fans")
    case .diagnostics: return L10n.string("Diagnostics")
    case .privacy: return L10n.string("Privacy")
    }
  }

  var subtitle: String {
    switch self {
    case .general: return L10n.string("Sampling and application behavior")
    case .alerts: return L10n.string("Local warnings and thresholds")
    case .menuBar: return L10n.string("Choose what is always visible")
    case .fans: return L10n.string("Monitoring and safe cooling control")
    case .diagnostics: return L10n.string("Sensor health and support bundle")
    case .privacy: return L10n.string("Local-only data policy")
    }
  }

  var symbol: String {
    switch self {
    case .general: return "slider.horizontal.3"
    case .alerts: return "bell.badge.fill"
    case .menuBar: return "menubar.rectangle"
    case .fans: return "fan.fill"
    case .diagnostics: return "stethoscope"
    case .privacy: return "hand.raised.fill"
    }
  }
}

struct PreferencesView: View {
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var settings: SettingsStore
  @EnvironmentObject private var fanControl: FanControlClient
  @State private var selection: PreferencesSection = .general

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      content
    }
    .frame(minWidth: 860, minHeight: 620)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Image(systemName: "waveform.path.ecg.rectangle.fill")
          .font(.title2)
          .foregroundStyle(Color.accentColor)
        VStack(alignment: .leading, spacing: 1) {
          Text("MacVitals").font(.headline)
          Text(L10n.string("Preferences"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 14)
      .padding(.bottom, 8)

      ForEach(PreferencesSection.allCases) { section in
        Button {
          selection = section
        } label: {
          HStack(spacing: 10) {
            Image(systemName: section.symbol)
              .font(.system(size: 15, weight: .semibold))
              .frame(width: 24)
              .foregroundStyle(selection == section ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
              Text(section.title)
                .font(.subheadline.weight(.semibold))
              Text(section.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 11)
          .padding(.vertical, 9)
          .background(
            selection == section ? Color.accentColor.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9))
          .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
      }

      Spacer()

      HStack(spacing: 7) {
        Circle()
          .fill(coordinator.isRunning ? Color.green : Color.orange)
          .frame(width: 8, height: 8)
        Text(coordinator.isRunning ? L10n.string("Live monitoring") : L10n.string("Monitoring paused"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 14)
    }
    .padding(.vertical, 16)
    .padding(.horizontal, 10)
    .frame(width: 230)
    .background(.quaternary.opacity(0.15))
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 3) {
          Text(selection.title)
            .font(.title2.bold())
          Text(selection.subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: selection.symbol)
          .font(.title)
          .foregroundStyle(Color.accentColor.opacity(0.8))
      }
      .padding(.horizontal, 24)
      .padding(.top, 20)
      .padding(.bottom, 14)

      Divider()

      Group {
        switch selection {
        case .general: generalTab
        case .alerts: alertsTab
        case .menuBar: menuBarTab
        case .fans: fansTab
        case .diagnostics:
          DiagnosticsView(
            snapshot: coordinator.snapshot,
            samplingHealth: coordinator.samplingHealth)
        case .privacy: privacyTab
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var generalTab: some View {
    ScrollView {
      VStack(spacing: 14) {
        SettingsCard(
          title: L10n.string("Monitoring frequency"),
          subtitle: L10n.string("Choose how often live metrics and charts refresh."),
          symbol: "timer") {
            VStack(alignment: .leading, spacing: 10) {
              Picker("Update interval", selection: $settings.samplingInterval) {
                ForEach(SamplingIntervalPolicy.supportedValues, id: \.self) {
                  Text("\($0, specifier: "%g") s").tag($0)
                }
              }
              .labelsHidden()
              .pickerStyle(.segmented)
              .accessibilityIdentifier("samplingIntervalPicker")

              HStack(spacing: 7) {
                Image(systemName: settings.samplingInterval <= 2 ? "bolt.fill" : "leaf.fill")
                Text(samplingIntervalDescription)
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }

        SettingsCard(
          title: L10n.string("Application"),
          subtitle: L10n.string("Control how MacVitals appears and starts."),
          symbol: "macwindow") {
            VStack(spacing: 12) {
              preferenceToggle(
                title: L10n.string("Show in Dock"),
                detail: L10n.string("Keep a regular application icon in the Dock."),
                symbol: "dock.rectangle",
                isOn: $settings.showInDock)
                .accessibilityIdentifier("showInDockToggle")

              Divider()

              VStack(alignment: .leading, spacing: 5) {
                preferenceToggle(
                  title: L10n.string("Launch at login"),
                  detail: L10n.string("Start monitoring automatically after you sign in."),
                  symbol: "power.circle",
                  isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { enabled in settings.setLaunchAtLogin(enabled) }))
                  .accessibilityIdentifier("launchAtLoginToggle")

                if let message = settings.launchAtLoginState.message {
                  Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 36)
                    .accessibilityIdentifier("launchAtLoginStatusMessage")
                }
              }
            }
          }

        SettingsCard(
          title: L10n.string("Current session"),
          subtitle: L10n.string("A quick view of the active monitoring loop."),
          symbol: "waveform.path.ecg") {
            HStack(spacing: 12) {
              sessionStat(
                title: L10n.string("Interval"),
                value: L10n.format("%g s", settings.samplingInterval),
                symbol: "clock")
              sessionStat(
                title: L10n.string("Sensors"),
                value: L10n.format("%d active", activeSensorCount),
                symbol: "sensor.fill")
              sessionStat(
                title: L10n.string("Temperature sensors"),
                value: "\(coordinator.snapshot.temperature.value?.sensors.count ?? 0)",
                symbol: "thermometer.medium")
            }
          }
      }
      .padding(24)
    }
  }

  private var alertsTab: some View {
    ScrollView {
      VStack(spacing: 14) {
        SettingsCard(
          title: L10n.string("Local notifications"),
          subtitle: L10n.string("Warnings stay on this Mac and are sent only when a state changes."),
          symbol: "bell.badge.fill") {
            VStack(alignment: .leading, spacing: 10) {
              preferenceToggle(
                title: L10n.string("Enable local alerts"),
                detail: L10n.string("Allow MacVitals to warn about important system changes."),
                symbol: "bell.fill",
                isOn: $settings.notificationsEnabled)
                .accessibilityIdentifier("notificationsEnabledToggle")

              if settings.notificationsEnabled,
                let message = settings.notificationAuthorizationState.message
              {
                Label(message, systemImage: "info.circle")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .padding(.leading, 36)
                  .accessibilityIdentifier("notificationAuthorizationStatusMessage")
              }
            }
          }

        SettingsCard(
          title: L10n.string("Active thresholds"),
          subtitle: L10n.string("Fine-tune when the current alert rules should trigger."),
          symbol: "gauge.with.dots.needle.67percent") {
            VStack(spacing: 16) {
              thresholdRow(
                title: L10n.string("Memory threshold"),
                detail: L10n.string("Notify when memory use stays above this level."),
                symbol: "memorychip",
                value: $settings.memoryAlertThreshold,
                range: 50...100,
                identifier: "memoryAlertThresholdSlider")
              Divider()
              thresholdRow(
                title: L10n.string("Low battery threshold"),
                detail: L10n.string("Notify while running on battery below this level."),
                symbol: "battery.25percent",
                value: $settings.lowBatteryAlertThreshold,
                range: 5...50,
                identifier: "lowBatteryAlertThresholdSlider")
            }
            .disabled(!settings.notificationsEnabled)
          }

        SettingsCard(
          title: L10n.string("Planned alerts"),
          subtitle: L10n.string("The layout is ready for additional notification rules."),
          symbol: "sparkles") {
            VStack(spacing: 10) {
              plannedAlert(
                title: L10n.string("Processor temperature"),
                detail: L10n.string("Warn when processor temperature remains high."),
                symbol: "thermometer.high")
              Divider()
              plannedAlert(
                title: L10n.string("Fan failure"),
                detail: L10n.string("Warn when a fan stops reporting expected RPM."),
                symbol: "fan.badge.exclamationmark")
              Divider()
              plannedAlert(
                title: L10n.string("Adapter overload"),
                detail: L10n.string("Warn when the adapter cannot support the current load."),
                symbol: "powerplug.fill")
            }
          }
      }
      .padding(24)
    }
  }

  private var menuBarTab: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 14) {
          SettingsCard(
            title: L10n.string("Live preview"),
            subtitle: L10n.string("This is how the selected metrics appear in the menu bar."),
            symbol: "menubar.rectangle") {
              HStack {
                Image(systemName: "apple.logo")
                  .foregroundStyle(.secondary)
                Text(MenuBarRenderer.render(
                  snapshot: coordinator.snapshot,
                  metrics: settings.enabledMetrics,
                  maximumCharacters: 120))
                  .font(.system(.body, design: .rounded).monospacedDigit())
                  .lineLimit(1)
                  .minimumScaleFactor(0.65)
                Spacer()
              }
              .padding(11)
              .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

          SettingsCard(
            title: L10n.string("Preset"),
            subtitle: L10n.string("Start with a sensible metric set, then customize it."),
            symbol: "square.grid.2x2") {
              Picker("Preset", selection: $settings.selectedPreset) {
                ForEach(MenuPreset.allCases) { preset in
                  Text(preset.displayName).tag(preset)
                }
              }
              .pickerStyle(.segmented)
              .accessibilityIdentifier("menuPresetPicker")
            }

          SettingsCard(
            title: L10n.string("Shown in menu bar"),
            subtitle: L10n.string("Enable metrics, change their order, and use distinct icons at a glance."),
            symbol: "list.bullet.rectangle") {
              List {
                Section("Shown in menu bar") {
                  ForEach(settings.enabledMetrics) { metric in
                    menuMetricRow(metric, enabled: true)
                      .accessibilityIdentifier("shownMetric.\(metric.rawValue)")
                  }
                  .onMove(perform: settings.move)
                }

                if !settings.hiddenMetrics.isEmpty {
                  Section("Hidden metrics") {
                    ForEach(settings.hiddenMetrics) { metric in
                      menuMetricRow(metric, enabled: false)
                    }
                  }
                }
              }
              .listStyle(.inset)
              .frame(minHeight: 250)
              .accessibilityIdentifier("menuMetricLayoutList")

              HStack {
                Text(L10n.string("Drag visible metrics to change their order."))
                  .font(.caption)
                  .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { settings.resetMenuLayout() }
                  .accessibilityIdentifier("restoreDefaultsButton")
              }
            }
        }
        .padding(24)
      }
    }
  }

  private var fansTab: some View {
    ScrollView {
      VStack(spacing: 14) {
        SettingsCard(
          title: L10n.string("Fan control status"),
          subtitle: L10n.string("Monitoring works in every build. Control requires a signed helper approved by macOS."),
          symbol: "shield.lefthalf.filled") {
            FanControlSetupStatusView()
          }

        SettingsCard(
          title: L10n.string("Fans"),
          subtitle: L10n.string("Inspect both fans and apply only temporary, safety-bounded cooling boosts."),
          symbol: "fan.fill") {
            FanControlView()
          }
      }
      .padding(24)
    }
  }

  private var privacyTab: some View {
    ScrollView {
      VStack(spacing: 14) {
        SettingsCard(
          title: L10n.string("Local by design"),
          subtitle: L10n.string("Your measurements stay on this Mac."),
          symbol: "lock.shield.fill") {
            Label(
              L10n.string(
                "MacVitals has no accounts, telemetry, analytics, ads, or network backend. Measurements and preferences remain on this Mac."),
              systemImage: "checkmark.shield.fill")
              .accessibilityIdentifier("privacyLocalOnlySummary")
          }

        SettingsCard(
          title: L10n.string("Safe support bundles"),
          subtitle: L10n.string("Diagnostic exports are deliberately redacted."),
          symbol: "doc.badge.gearshape") {
            Label(
              L10n.string(
                "The support bundle redacts home paths and does not include serial numbers, Apple ID, user documents, network data, or stable GPU registry identifiers."),
              systemImage: "eye.slash.fill")
              .accessibilityIdentifier("privacySupportBundleSummary")
          }
      }
      .padding(24)
    }
  }

  private var samplingIntervalDescription: String {
    switch settings.samplingInterval {
    case ...2: return L10n.string("Fastest response with higher sensor and energy overhead.")
    case ...5: return L10n.string("Balanced live monitoring for everyday use.")
    case ...15: return L10n.string("Lower overhead while keeping useful history.")
    default: return L10n.string("Lowest overhead for long-running monitoring.")
    }
  }

  private var activeSensorCount: Int {
    let snapshot = coordinator.snapshot
    return [
      snapshot.cpu.value != nil,
      snapshot.memory.value != nil,
      snapshot.gpu.value != nil,
      snapshot.battery.value != nil,
      snapshot.adapter.value != nil,
      snapshot.temperature.value != nil,
      snapshot.fans.value != nil,
      snapshot.power.value != nil,
    ].filter { $0 }.count
  }

  private func preferenceToggle(
    title: String,
    detail: String,
    symbol: String,
    isOn: Binding<Bool>
  ) -> some View {
    HStack(spacing: 11) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(Color.accentColor)
        .frame(width: 25)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Toggle("", isOn: isOn)
        .labelsHidden()
        .toggleStyle(.switch)
    }
  }

  private func thresholdRow(
    title: String,
    detail: String,
    symbol: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    identifier: String
  ) -> some View {
    HStack(spacing: 11) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(Color.accentColor)
        .frame(width: 25)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Slider(value: value, in: range, step: 5)
        .frame(width: 180)
        .accessibilityIdentifier(identifier)
      Text("\(Int(value.wrappedValue))%")
        .font(.body.monospacedDigit())
        .frame(width: 45, alignment: .trailing)
    }
  }

  private func plannedAlert(title: String, detail: String, symbol: String) -> some View {
    HStack(spacing: 11) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 25)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Text(L10n.string("Coming soon"))
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
  }

  private func menuMetricRow(_ metric: MenuMetric, enabled: Bool) -> some View {
    HStack(spacing: 10) {
      Image(systemName: metric.defaultSymbol)
        .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
        .frame(width: 22)
      Text(metric.displayName)
      Spacer()
      Button {
        settings.setMetric(metric, enabled: !enabled)
      } label: {
        Image(systemName: enabled ? "eye.slash" : "plus.circle.fill")
      }
      .buttonStyle(.borderless)
      .help(enabled ? L10n.string("Hide metric") : L10n.string("Show metric"))
      .accessibilityLabel(
        enabled ? L10n.format("Hide %@", metric.displayName) : L10n.format("Show %@", metric.displayName))
      .accessibilityIdentifier("\(enabled ? "hideMetric" : "showMetric").\(metric.rawValue)")
    }
  }

  private func sessionStat(title: String, value: String, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Label(title, systemImage: symbol)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.headline.monospacedDigit())
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 9))
  }
}

private struct SettingsCard<Content: View>: View {
  let title: String
  let subtitle: String
  let symbol: String
  @ViewBuilder let content: Content

  init(
    title: String,
    subtitle: String,
    symbol: String,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.symbol = symbol
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.title3)
          .foregroundStyle(Color.accentColor)
          .frame(width: 25)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.headline)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
      }
      content
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 13))
    .overlay(
      RoundedRectangle(cornerRadius: 13)
        .stroke(.quaternary.opacity(0.42), lineWidth: 1))
  }
}
