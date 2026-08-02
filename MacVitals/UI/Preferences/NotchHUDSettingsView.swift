import AppKit
import SwiftUI

@MainActor
final class NotchHUDSettingsWindowController: NSWindowController, NSWindowDelegate {
  init(coordinator: MetricsCoordinator, settings: SettingsStore) {
    let rootView = NotchHUDSettingsView()
      .environmentObject(coordinator)
      .environmentObject(settings)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 780, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = L10n.string("HUD Settings")
    window.minSize = NSSize(width: 700, height: 620)
    window.isReleasedWhenClosed = false
    window.center()
    window.contentViewController = NSHostingController(rootView: rootView)

    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

private enum HUDMetricPlacement: String, CaseIterable, Identifiable {
  case hidden
  case left
  case right

  var id: String { rawValue }

  var title: String {
    switch self {
    case .hidden: return L10n.string("Hidden")
    case .left: return L10n.string("Left")
    case .right: return L10n.string("Right")
    }
  }
}

@MainActor
struct NotchHUDSettingsView: View {
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()

      ScrollView {
        VStack(spacing: 14) {
          livePreviewCard
          visibilityCard
          presetCard
          panelCard
          sensorCard
          appearanceCard
          displayCard
          resetRow
        }
        .padding(22)
      }
    }
    .frame(minWidth: 700, minHeight: 620)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "macbook")
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 3) {
        Text(L10n.string("HUD Settings"))
          .font(.title2.bold())
        Text(L10n.string("Configure the compact panels around the camera notch."))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Toggle(L10n.string("Enabled"), isOn: $settings.showAroundStatusBar)
        .toggleStyle(.switch)
        .accessibilityIdentifier("notchHUDEnabledToggle")
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 16)
  }

  private var livePreviewCard: some View {
    HUDSettingsCard(
      title: L10n.string("Live preview"),
      subtitle: L10n.string("The preview uses the current sensor values and applies changes immediately."),
      symbol: "eye.fill") {
        NotchHUDPreview(
          snapshot: coordinator.snapshot,
          configuration: settings.notchHUDConfiguration)
          .frame(height: 64)
          .accessibilityIdentifier("notchHUDLivePreview")
      }
  }

  private var visibilityCard: some View {
    HUDSettingsCard(
      title: L10n.string("Visibility"),
      subtitle: L10n.string("Choose which side panels are shown."),
      symbol: "rectangle.split.2x1") {
        VStack(spacing: 12) {
          HUDToggleRow(
            title: L10n.string("Left panel"),
            detail: L10n.string("Performance sensors beside the left edge of the notch."),
            symbol: "rectangle.lefthalf.inset.filled",
            isOn: configurationBinding(\.showLeftPanel))
          Divider()
          HUDToggleRow(
            title: L10n.string("Right panel"),
            detail: L10n.string("Cooling, battery and power sensors beside the right edge."),
            symbol: "rectangle.righthalf.inset.filled",
            isOn: configurationBinding(\.showRightPanel))
        }
      }
  }

  private var presetCard: some View {
    HUDSettingsCard(
      title: L10n.string("Preset"),
      subtitle: L10n.string("Start from a compact, balanced or detailed layout."),
      symbol: "square.grid.2x2") {
        Picker(L10n.string("Preset"), selection: presetBinding) {
          ForEach(NotchHUDPreset.allCases) { preset in
            Text(preset.displayName).tag(preset)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityIdentifier("notchHUDPresetPicker")
      }
  }

  private var panelCard: some View {
    HUDSettingsCard(
      title: L10n.string("Sensors per panel"),
      subtitle: L10n.string("Limit how many configured sensors are visible on each side."),
      symbol: "number.square.fill") {
        VStack(spacing: 14) {
          visibleCountRow(side: .left)
          Divider()
          visibleCountRow(side: .right)
        }
      }
  }

  private var sensorCard: some View {
    HUDSettingsCard(
      title: L10n.string("Sensor placement and order"),
      subtitle: L10n.string("Assign every sensor to the left panel, right panel or hide it."),
      symbol: "sensor.tag.radiowaves.forward.fill") {
        VStack(spacing: 0) {
          ForEach(Array(MenuMetric.allCases.enumerated()), id: \.element) { index, metric in
            sensorRow(metric)
            if index < MenuMetric.allCases.count - 1 { Divider() }
          }
        }
      }
  }

  private var appearanceCard: some View {
    HUDSettingsCard(
      title: L10n.string("Appearance"),
      subtitle: L10n.string("Tune density, typography and visual separation."),
      symbol: "paintbrush.fill") {
        VStack(alignment: .leading, spacing: 14) {
          labeledPicker(
            title: L10n.string("Density"),
            selection: configurationBinding(\.density),
            values: NotchHUDDensity.allCases)
          labeledPicker(
            title: L10n.string("Text size"),
            selection: configurationBinding(\.textSize),
            values: NotchHUDTextSize.allCases)

          VStack(alignment: .leading, spacing: 7) {
            HStack {
              Text(L10n.string("Background strength"))
                .font(.subheadline.weight(.semibold))
              Spacer()
              Text("\(Int(settings.notchHUDConfiguration.backgroundOpacity * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Slider(
              value: configurationBinding(\.backgroundOpacity),
              in: 0.2...0.95,
              step: 0.05)
              .accessibilityIdentifier("notchHUDBackgroundOpacitySlider")
          }

          Divider()
          HUDToggleRow(
            title: L10n.string("Show short labels"),
            detail: L10n.string("Add labels such as CPU, RAM, BAT and PWR."),
            symbol: "character.textbox",
            isOn: configurationBinding(\.showLabels))
          Divider()
          HUDToggleRow(
            title: L10n.string("Show separators"),
            detail: L10n.string("Draw subtle dividers between neighboring sensors."),
            symbol: "line.vertical",
            isOn: configurationBinding(\.showSeparators))
          Divider()
          HUDToggleRow(
            title: L10n.string("Hide unavailable sensors"),
            detail: L10n.string("Remove missing readings instead of showing a dash."),
            symbol: "eye.slash",
            isOn: configurationBinding(\.hideUnavailableMetrics))
        }
      }
  }

  private var displayCard: some View {
    HUDSettingsCard(
      title: L10n.string("Displays"),
      subtitle: L10n.string("Control behavior on displays that do not have a camera notch."),
      symbol: "display.2") {
        HUDToggleRow(
          title: L10n.string("Show on displays without a notch"),
          detail: L10n.string("Keep the two capsules centered in the menu bar on external displays."),
          symbol: "display",
          isOn: configurationBinding(\.showOnDisplaysWithoutNotch))
      }
  }

  private var resetRow: some View {
    HStack {
      Text(L10n.string("HUD settings are stored locally on this Mac."))
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Button(L10n.string("Restore HUD Defaults")) {
        settings.resetNotchHUDConfiguration()
      }
      .accessibilityIdentifier("restoreNotchHUDDefaultsButton")
    }
  }

  private func visibleCountRow(side: NotchHUDSide) -> some View {
    let configuredCount = metrics(for: side).count
    let visibleCount = side == .left
      ? settings.notchHUDConfiguration.leftVisibleCount
      : settings.notchHUDConfiguration.rightVisibleCount
    let panelEnabled = side == .left
      ? settings.notchHUDConfiguration.showLeftPanel
      : settings.notchHUDConfiguration.showRightPanel

    return HStack(spacing: 12) {
      Image(systemName: side == .left ? "arrow.left.to.line" : "arrow.right.to.line")
        .frame(width: 24)
        .foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 2) {
        Text(side.displayName)
          .font(.subheadline.weight(.semibold))
        Text(
          L10n.format(
            "%d of %d configured sensors visible",
            panelEnabled ? min(visibleCount, configuredCount) : 0,
            configuredCount))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Stepper(
        value: visibleCountBinding(side: side),
        in: 1...max(1, min(configuredCount, NotchHUDConfigurationPolicy.maximumMetricsPerSide))) {
          Text("\(visibleCount)")
            .font(.body.monospacedDigit())
            .frame(minWidth: 22)
        }
        .disabled(configuredCount == 0 || !panelEnabled)
        .accessibilityIdentifier("notchHUDVisibleCount.\(side.rawValue)")
    }
  }

  private func sensorRow(_ metric: MenuMetric) -> some View {
    let placement = placement(for: metric)
    return HStack(spacing: 10) {
      Image(systemName: metric.defaultSymbol)
        .frame(width: 22)
        .foregroundStyle(Color.accentColor)
      Text(metric.displayName)
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)

      if placement != .hidden {
        Button {
          settings.moveNotchHUDMetric(metric, towardStart: true)
        } label: {
          Image(systemName: "chevron.up")
        }
        .buttonStyle(.borderless)
        .help(L10n.string("Move earlier"))

        Button {
          settings.moveNotchHUDMetric(metric, towardStart: false)
        } label: {
          Image(systemName: "chevron.down")
        }
        .buttonStyle(.borderless)
        .help(L10n.string("Move later"))
      }

      Picker(metric.displayName, selection: placementBinding(for: metric)) {
        ForEach(HUDMetricPlacement.allCases) { option in
          Text(option.title).tag(option)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 230)
      .accessibilityIdentifier("notchHUDPlacement.\(metric.rawValue)")
    }
    .padding(.vertical, 8)
  }

  private func labeledPicker<Value: Identifiable & Hashable>(
    title: String,
    selection: Binding<Value>,
    values: [Value]
  ) -> some View where Value.ID == String {
    HStack {
      Text(title)
        .font(.subheadline.weight(.semibold))
      Spacer()
      Picker(title, selection: selection) {
        ForEach(values) { value in
          if let density = value as? NotchHUDDensity {
            Text(density.displayName).tag(value)
          } else if let textSize = value as? NotchHUDTextSize {
            Text(textSize.displayName).tag(value)
          }
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 320)
    }
  }

  private var presetBinding: Binding<NotchHUDPreset> {
    Binding(
      get: { settings.notchHUDPreset },
      set: { settings.applyNotchHUDPreset($0) })
  }

  private func configurationBinding<Value>(
    _ keyPath: WritableKeyPath<NotchHUDConfiguration, Value>
  ) -> Binding<Value> {
    Binding(
      get: { settings.notchHUDConfiguration[keyPath: keyPath] },
      set: { newValue in
        var configuration = settings.notchHUDConfiguration
        configuration[keyPath: keyPath] = newValue
        settings.notchHUDConfiguration = configuration
      })
  }

  private func visibleCountBinding(side: NotchHUDSide) -> Binding<Int> {
    switch side {
    case .left: return configurationBinding(\.leftVisibleCount)
    case .right: return configurationBinding(\.rightVisibleCount)
    }
  }

  private func metrics(for side: NotchHUDSide) -> [MenuMetric] {
    switch side {
    case .left: return settings.notchHUDConfiguration.leftMetrics
    case .right: return settings.notchHUDConfiguration.rightMetrics
    }
  }

  private func placement(for metric: MenuMetric) -> HUDMetricPlacement {
    switch settings.notchHUDConfiguration.placement(of: metric) {
    case .left: return .left
    case .right: return .right
    case nil: return .hidden
    }
  }

  private func placementBinding(for metric: MenuMetric) -> Binding<HUDMetricPlacement> {
    Binding(
      get: { placement(for: metric) },
      set: { placement in
        switch placement {
        case .hidden: settings.setNotchHUDMetric(metric, side: nil)
        case .left: settings.setNotchHUDMetric(metric, side: .left)
        case .right: settings.setNotchHUDMetric(metric, side: .right)
        }
      })
  }
}

@MainActor
private struct NotchHUDPreview: View {
  let snapshot: SystemSnapshot
  let configuration: NotchHUDConfiguration

  var body: some View {
    GeometryReader { geometry in
      let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
      let leftWidth = normalized.showLeftPanel
        ? NotchHUDLayout.preferredPanelWidth(
          metricCount: normalized.metrics(for: .left).count,
          configuration: normalized)
        : 0
      let rightWidth = normalized.showRightPanel
        ? NotchHUDLayout.preferredPanelWidth(
          metricCount: normalized.metrics(for: .right).count,
          configuration: normalized)
        : 0
      let notchWidth: CGFloat = 88
      let totalWidth = leftWidth + rightWidth + notchWidth + 16
      let scale = min(1, max(0.55, (geometry.size.width - 20) / max(totalWidth, 1)))

      ZStack {
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.black.opacity(0.88))

        HStack(spacing: 8) {
          if normalized.showLeftPanel {
            NotchHUDSideContentView(
              snapshot: snapshot,
              configuration: normalized,
              side: .left)
              .frame(width: leftWidth, height: CGFloat(normalized.density.panelHeight))
          }

          UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 10,
            bottomTrailingRadius: 10,
            topTrailingRadius: 0)
            .fill(Color.black)
            .frame(width: notchWidth, height: 30)
            .accessibilityHidden(true)

          if normalized.showRightPanel {
            NotchHUDSideContentView(
              snapshot: snapshot,
              configuration: normalized,
              side: .right)
              .frame(width: rightWidth, height: CGFloat(normalized.density.panelHeight))
          }
        }
        .scaleEffect(scale)
      }
    }
  }
}

private struct HUDToggleRow: View {
  let title: String
  let detail: String
  let symbol: String
  @Binding var isOn: Bool

  var body: some View {
    Toggle(isOn: $isOn) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .frame(width: 24)
          .foregroundStyle(Color.accentColor)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline.weight(.semibold))
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .toggleStyle(.switch)
  }
}

private struct HUDSettingsCard<Content: View>: View {
  let title: String
  let subtitle: String
  let symbol: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Color.accentColor)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.headline)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      content
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.20), in: RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(.quaternary.opacity(0.45), lineWidth: 1))
  }
}