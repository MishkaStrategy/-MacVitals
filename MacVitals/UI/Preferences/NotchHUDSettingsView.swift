import AppKit
import SwiftUI

@MainActor
final class NotchHUDSettingsWindowController: NSWindowController {
  init(coordinator: MetricsCoordinator, settings: SettingsStore) {
    let rootView = NotchHUDSettingsView()
      .environmentObject(coordinator)
      .environmentObject(settings)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1_040, height: 820),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = L10n.string("HUD Settings")
    window.minSize = NSSize(width: 900, height: 700)
    window.isReleasedWhenClosed = false
    window.center()
    window.contentViewController = NSHostingController(rootView: rootView)

    super.init(window: window)
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
  @State private var selectedMetric: MenuMetric = .cpu

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()

      ScrollView {
        VStack(spacing: 14) {
          livePreviewCard
          presetCard
          visibilityCard
          panelCard
          tileEditorCard
          appearanceCard
          displayCard
          resetRow
        }
        .padding(22)
      }
    }
    .frame(minWidth: 900, minHeight: 700)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "rectangle.3.group.fill")
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(Color.accentColor)
      VStack(alignment: .leading, spacing: 3) {
        Text(L10n.string("HUD Settings"))
          .font(.title2.bold())
        Text(L10n.string("Build and style every HUD tile independently."))
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
      subtitle: L10n.string("The preview uses current readings and updates every tile immediately."),
      symbol: "eye.fill") {
        NotchHUDPreview(
          snapshot: coordinator.snapshot,
          configuration: settings.notchHUDConfiguration)
          .frame(height: 76)
          .accessibilityIdentifier("notchHUDLivePreview")
      }
  }

  private var presetCard: some View {
    HUDSettingsCard(
      title: L10n.string("Layout preset"),
      subtitle: L10n.string("Presets reset the panel layout and tile styles to a known profile."),
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

  private var visibilityCard: some View {
    HUDSettingsCard(
      title: L10n.string("Panel visibility"),
      subtitle: L10n.string("Choose which side panels are available for tiles."),
      symbol: "rectangle.split.2x1") {
        VStack(spacing: 12) {
          HUDToggleRow(
            title: L10n.string("Left panel"),
            detail: L10n.string("Performance tiles beside the left edge of the notch."),
            symbol: "rectangle.lefthalf.inset.filled",
            isOn: configurationBinding(\.showLeftPanel))
          Divider()
          HUDToggleRow(
            title: L10n.string("Right panel"),
            detail: L10n.string("Cooling, battery and power tiles beside the right edge."),
            symbol: "rectangle.righthalf.inset.filled",
            isOn: configurationBinding(\.showRightPanel))
        }
      }
  }

  private var panelCard: some View {
    HUDSettingsCard(
      title: L10n.string("Tiles per panel"),
      subtitle: L10n.string("Limit visible tiles without deleting their configuration."),
      symbol: "number.square.fill") {
        VStack(spacing: 14) {
          visibleCountRow(side: .left)
          Divider()
          visibleCountRow(side: .right)
        }
      }
  }

  private var tileEditorCard: some View {
    HUDSettingsCard(
      title: L10n.string("Tile editor"),
      subtitle: L10n.string("Select a tile, place it, then configure its content, size, color and thresholds."),
      symbol: "slider.horizontal.3") {
        HUDTileEditor(selectedMetric: $selectedMetric)
          .environmentObject(settings)
      }
  }

  private var appearanceCard: some View {
    HUDSettingsCard(
      title: L10n.string("Panel appearance"),
      subtitle: L10n.string("These settings provide defaults around the individually styled tiles."),
      symbol: "paintbrush.fill") {
        VStack(alignment: .leading, spacing: 14) {
          densityPickerRow
          textSizePickerRow

          VStack(alignment: .leading, spacing: 7) {
            HStack {
              Text(L10n.string("Panel background strength"))
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
            title: L10n.string("Labels in automatic tile mode"),
            detail: L10n.string("Automatic tiles use short labels such as CPU, RAM, BAT and PWR."),
            symbol: "character.textbox",
            isOn: configurationBinding(\.showLabels))
          Divider()
          HUDToggleRow(
            title: L10n.string("Show separators"),
            detail: L10n.string("Draw subtle dividers between neighboring tiles."),
            symbol: "line.vertical",
            isOn: configurationBinding(\.showSeparators))
          Divider()
          HUDToggleRow(
            title: L10n.string("Hide unavailable tiles"),
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
          detail: L10n.string("Keep the capsules centered in the menu bar on external displays."),
          symbol: "display",
          isOn: configurationBinding(\.showOnDisplaysWithoutNotch))
      }
  }

  private var resetRow: some View {
    HStack {
      Text(L10n.string("HUD and tile settings are stored locally on this Mac."))
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Button(L10n.string("Restore HUD Defaults")) {
        settings.resetNotchHUDConfiguration()
        selectedMetric = .cpu
      }
      .accessibilityIdentifier("restoreNotchHUDDefaultsButton")
    }
  }

  private var densityPickerRow: some View {
    HStack {
      Text(L10n.string("Panel density"))
        .font(.subheadline.weight(.semibold))
      Spacer()
      Picker(L10n.string("Density"), selection: configurationBinding(\.density)) {
        ForEach(NotchHUDDensity.allCases) { density in
          Text(density.displayName).tag(density)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 360)
    }
  }

  private var textSizePickerRow: some View {
    HStack {
      Text(L10n.string("Base text size"))
        .font(.subheadline.weight(.semibold))
      Spacer()
      Picker(L10n.string("Text size"), selection: configurationBinding(\.textSize)) {
        ForEach(NotchHUDTextSize.allCases) { textSize in
          Text(textSize.displayName).tag(textSize)
        }
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: 360)
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
            "%d of %d configured tiles visible",
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

  private var presetBinding: Binding<NotchHUDPreset> {
    Binding(
      get: { settings.notchHUDPreset },
      set: {
        settings.applyNotchHUDPreset($0)
        selectedMetric = .cpu
      })
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
}

@MainActor
private struct HUDTileEditor: View {
  @EnvironmentObject private var settings: SettingsStore
  @Binding var selectedMetric: MenuMetric

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      tileList
        .frame(width: 300)
      Divider()
      tileInspector
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private var tileList: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(L10n.string("Tiles"))
          .font(.subheadline.bold())
        Spacer()
        Button(L10n.string("Reset all")) {
          resetAllTiles()
        }
        .buttonStyle(.borderless)
      }

      VStack(spacing: 4) {
        ForEach(MenuMetric.allCases) { metric in
          tileListRow(metric)
        }
      }
    }
  }

  private func tileListRow(_ metric: MenuMetric) -> some View {
    let placement = placement(for: metric)
    let isSelected = selectedMetric == metric

    return HStack(spacing: 8) {
      Button {
        selectedMetric = metric
      } label: {
        HStack(spacing: 8) {
          Image(systemName: settings.notchHUDConfiguration.tileConfiguration(for: metric).symbolName)
            .frame(width: 18)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
          VStack(alignment: .leading, spacing: 1) {
            Text(metric.displayName)
              .font(.subheadline.weight(isSelected ? .semibold : .regular))
            Text(placement.title)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

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
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .background(
      isSelected ? Color.accentColor.opacity(0.12) : Color.clear,
      in: RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1))
    .accessibilityIdentifier("notchHUDTileList.\(metric.rawValue)")
  }

  private var tileInspector: some View {
    VStack(alignment: .leading, spacing: 14) {
      inspectorHeader
      Divider()
      inspectorRow(L10n.string("Placement")) {
        Picker(L10n.string("Placement"), selection: placementBinding) {
          ForEach(HUDMetricPlacement.allCases) { option in
            Text(option.title).tag(option)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 330)
      }

      inspectorSection(L10n.string("Content"), symbol: "textformat") {
        inspectorRow(L10n.string("Composition")) {
          Picker(L10n.string("Composition"), selection: tileBinding(\.contentStyle)) {
            ForEach(NotchHUDTileContentStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          .labelsHidden()
          .frame(width: 330)
        }

        inspectorRow(L10n.string("Custom label")) {
          TextField(L10n.string("Short label"), text: tileBinding(\.customLabel))
            .textFieldStyle(.roundedBorder)
            .frame(width: 210)
        }

        inspectorRow(L10n.string("Icon")) {
          Picker(L10n.string("Icon"), selection: tileBinding(\.symbolName)) {
            ForEach(selectedMetric.notchHUDSymbolOptions, id: \.self) { symbol in
              Label(symbol, systemImage: symbol).tag(symbol)
            }
          }
          .labelsHidden()
          .frame(width: 210)
        }
      }

      inspectorSection(L10n.string("Geometry and typography"), symbol: "rectangle.resize") {
        inspectorRow(L10n.string("Tile width")) {
          Picker(L10n.string("Tile width"), selection: tileBinding(\.size)) {
            ForEach(NotchHUDTileSize.allCases) { size in
              Text(size.displayName).tag(size)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 330)
        }

        inspectorRow(L10n.string("Content alignment")) {
          Picker(L10n.string("Content alignment"), selection: tileBinding(\.alignment)) {
            ForEach(NotchHUDTileAlignment.allCases) { alignment in
              Text(alignment.displayName).tag(alignment)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 330)
        }

        inspectorRow(L10n.string("Value emphasis")) {
          Picker(L10n.string("Value emphasis"), selection: tileBinding(\.emphasis)) {
            ForEach(NotchHUDTileEmphasis.allCases) { emphasis in
              Text(emphasis.displayName).tag(emphasis)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 330)
        }
      }

      inspectorSection(L10n.string("Value formatting"), symbol: "number") {
        inspectorRow(L10n.string("Precision")) {
          Picker(L10n.string("Precision"), selection: tileBinding(\.precision)) {
            ForEach(NotchHUDTilePrecision.allCases) { precision in
              Text(precision.displayName).tag(precision)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 330)
        }

        Toggle(L10n.string("Show measurement unit"), isOn: tileBinding(\.showsUnit))
          .toggleStyle(.switch)
      }

      inspectorSection(L10n.string("Color and background"), symbol: "paintpalette.fill") {
        inspectorRow(L10n.string("Value color")) {
          Picker(L10n.string("Value color"), selection: tileBinding(\.colorMode)) {
            ForEach(NotchHUDTileColorMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          .labelsHidden()
          .frame(width: 250)
        }

        if tile.colorMode == .custom {
          inspectorRow(L10n.string("Custom color")) {
            Picker(L10n.string("Custom color"), selection: tileBinding(\.accent)) {
              ForEach(NotchHUDTileAccent.allCases) { accent in
                Text(accent.displayName).tag(accent)
              }
            }
            .labelsHidden()
            .frame(width: 210)
          }
        }

        inspectorRow(L10n.string("Tile background")) {
          Picker(L10n.string("Tile background"), selection: tileBinding(\.backgroundStyle)) {
            ForEach(NotchHUDTileBackgroundStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 330)
        }

        if tile.backgroundStyle != .none {
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(L10n.string("Tile background strength"))
                .font(.caption.weight(.semibold))
              Spacer()
              Text("\(Int(tile.backgroundOpacity * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Slider(value: tileBinding(\.backgroundOpacity), in: 0...1, step: 0.05)
          }
        }
      }

      if tile.colorMode == .semantic {
        inspectorSection(L10n.string("Threshold colors"), symbol: "exclamationmark.triangle.fill") {
          inspectorRow(L10n.string("Threshold direction")) {
            Picker(
              L10n.string("Threshold direction"),
              selection: tileBinding(\.thresholdDirection)
            ) {
              ForEach(NotchHUDThresholdDirection.allCases) { direction in
                Text(direction.displayName).tag(direction)
              }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 330)
          }

          HStack(spacing: 18) {
            numericField(
              title: L10n.string("Warning"),
              value: tileBinding(\.warningThreshold))
            numericField(
              title: L10n.string("Critical"),
              value: tileBinding(\.criticalThreshold))
          }
        }
      }
    }
  }

  private var inspectorHeader: some View {
    HStack(spacing: 10) {
      Image(systemName: tile.symbolName)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(selectedMetric.displayName)
          .font(.headline)
        Text(L10n.string("Individual tile settings"))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(L10n.string("Copy style to all")) {
        copyStyleToAllTiles()
      }
      Button(L10n.string("Reset tile")) {
        resetSelectedTile()
      }
    }
  }

  private var tile: NotchHUDTileConfiguration {
    settings.notchHUDConfiguration.tileConfiguration(for: selectedMetric)
  }

  private func inspectorRow<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack {
      Text(title)
        .font(.caption.weight(.semibold))
      Spacer()
      content()
    }
  }

  private func inspectorSection<Content: View>(
    _ title: String,
    symbol: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: symbol)
        .font(.subheadline.bold())
        .foregroundStyle(.secondary)
      content()
    }
    .padding(12)
    .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
  }

  private func numericField(title: String, value: Binding<Double>) -> some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.caption.weight(.semibold))
      TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
        .textFieldStyle(.roundedBorder)
        .frame(width: 90)
    }
  }

  private var placementBinding: Binding<HUDMetricPlacement> {
    Binding(
      get: { placement(for: selectedMetric) },
      set: { placement in
        switch placement {
        case .hidden: settings.setNotchHUDMetric(selectedMetric, side: nil)
        case .left: settings.setNotchHUDMetric(selectedMetric, side: .left)
        case .right: settings.setNotchHUDMetric(selectedMetric, side: .right)
        }
      })
  }

  private func tileBinding<Value>(
    _ keyPath: WritableKeyPath<NotchHUDTileConfiguration, Value>
  ) -> Binding<Value> {
    Binding(
      get: { tile[keyPath: keyPath] },
      set: { newValue in
        var updatedTile = tile
        updatedTile[keyPath: keyPath] = newValue
        settings.notchHUDConfiguration = NotchHUDConfigurationPolicy.settingTile(
          updatedTile,
          for: selectedMetric,
          in: settings.notchHUDConfiguration)
      })
  }

  private func placement(for metric: MenuMetric) -> HUDMetricPlacement {
    switch settings.notchHUDConfiguration.placement(of: metric) {
    case .left: return .left
    case .right: return .right
    case nil: return .hidden
    }
  }

  private func resetSelectedTile() {
    settings.notchHUDConfiguration = NotchHUDConfigurationPolicy.resettingTile(
      selectedMetric,
      in: settings.notchHUDConfiguration)
  }

  private func resetAllTiles() {
    var configuration = settings.notchHUDConfiguration
    configuration.tileConfigurations = NotchHUDConfiguration.defaultTiles
    settings.notchHUDConfiguration = NotchHUDConfigurationPolicy.normalized(configuration)
  }

  private func copyStyleToAllTiles() {
    let source = tile
    var configuration = settings.notchHUDConfiguration
    for metric in MenuMetric.allCases {
      var target = configuration.tileConfiguration(for: metric)
      target.size = source.size
      target.contentStyle = source.contentStyle
      target.alignment = source.alignment
      target.emphasis = source.emphasis
      target.precision = source.precision
      target.showsUnit = source.showsUnit
      target.colorMode = source.colorMode
      target.accent = source.accent
      target.backgroundStyle = source.backgroundStyle
      target.backgroundOpacity = source.backgroundOpacity
      configuration.tileConfigurations[metric] = target
    }
    settings.notchHUDConfiguration = NotchHUDConfigurationPolicy.normalized(configuration)
  }
}

@MainActor
private struct NotchHUDPreview: View {
  let snapshot: SystemSnapshot
  let configuration: NotchHUDConfiguration

  var body: some View {
    GeometryReader { geometry in
      let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
      let leftMetrics = normalized.metrics(for: .left)
      let rightMetrics = normalized.metrics(for: .right)
      let leftWidth = normalized.showLeftPanel
        ? NotchHUDLayout.preferredPanelWidth(
          metrics: leftMetrics,
          configuration: normalized)
        : 0
      let rightWidth = normalized.showRightPanel
        ? NotchHUDLayout.preferredPanelWidth(
          metrics: rightMetrics,
          configuration: normalized)
        : 0
      let notchWidth: CGFloat = 88
      let totalWidth = leftWidth + rightWidth + notchWidth + 16
      let scale = min(1, max(0.42, (geometry.size.width - 20) / max(totalWidth, 1)))

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

          RoundedRectangle(cornerRadius: 9)
            .fill(Color.black)
            .frame(width: notchWidth, height: 28)
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
