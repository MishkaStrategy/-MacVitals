import SwiftUI

extension Notification.Name {
  static let openStatusBarHUDPreferences = Notification.Name("openStatusBarHUDPreferences")
}

private enum CompactHUDPlacement: String, CaseIterable, Identifiable {
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

  var side: NotchHUDSide? {
    switch self {
    case .hidden: return nil
    case .left: return .left
    case .right: return .right
    }
  }
}

@MainActor
struct CompactNotchHUDPreferencesView: View {
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var settings: SettingsStore
  @State private var selectedMetric: MenuMetric = .cpu
  @State private var showsTileAppearance = false
  @State private var showsThresholds = false

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 10) {
        previewCard
        layoutCard
        tileCard
        panelAppearanceCard
        displayCard
        resetRow
      }
      .padding(18)
    }
    .accessibilityIdentifier("notchHUDIntegratedSettings")
  }

  private var previewCard: some View {
    CompactHUDCard {
      HStack(spacing: 10) {
        Label(L10n.string("Live preview"), systemImage: "eye.fill")
          .font(.headline)
        Spacer()
        Toggle(L10n.string("Enabled"), isOn: $settings.showAroundStatusBar)
          .toggleStyle(.switch)
          .accessibilityIdentifier("notchHUDEnabledToggle")
      }

      CompactNotchHUDPreview(
        snapshot: coordinator.snapshot,
        configuration: settings.notchHUDConfiguration)
        .frame(height: 62)
        .accessibilityIdentifier("notchHUDLivePreview")
    }
  }

  private var layoutCard: some View {
    CompactHUDCard {
      HStack(spacing: 12) {
        Label(L10n.string("Layout preset"), systemImage: "square.grid.2x2")
          .font(.headline)
        Spacer()
        Picker(L10n.string("Preset"), selection: presetBinding) {
          ForEach(NotchHUDPreset.allCases) { preset in
            Text(preset.displayName).tag(preset)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: 390)
        .accessibilityIdentifier("notchHUDPresetPicker")
      }

      Divider()

      HStack(alignment: .top, spacing: 10) {
        panelSummary(side: .left)
        panelSummary(side: .right)
      }
    }
  }

  private var tileCard: some View {
    CompactHUDCard {
      HStack {
        Label(L10n.string("Tile editor"), systemImage: "slider.horizontal.3")
          .font(.headline)
        Spacer()
        Button(L10n.string("Reset tile")) {
          resetSelectedTile()
        }
        .buttonStyle(.borderless)
      }

      tileSelector
      Divider()

      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
        GridRow {
          compactLabel(L10n.string("Placement"))
          Picker(L10n.string("Placement"), selection: placementBinding) {
            ForEach(CompactHUDPlacement.allCases) { placement in
              Text(placement.title).tag(placement)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .accessibilityIdentifier("notchHUDPlacementPicker")
        }

        GridRow {
          compactLabel(L10n.string("Composition"))
          Picker(L10n.string("Composition"), selection: tileBinding(\.contentStyle)) {
            ForEach(NotchHUDTileContentStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }

        GridRow {
          compactLabel(L10n.string("Custom label"))
          TextField(L10n.string("Short label"), text: tileBinding(\.customLabel))
            .textFieldStyle(.roundedBorder)
        }

        GridRow {
          compactLabel(L10n.string("Icon"))
          Picker(L10n.string("Icon"), selection: tileBinding(\.symbolName)) {
            ForEach(selectedMetric.notchHUDSymbolOptions, id: \.self) { symbol in
              Label(symbol, systemImage: symbol).tag(symbol)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
        }

        GridRow {
          compactLabel(L10n.string("Tile width"))
          Picker(L10n.string("Tile width"), selection: tileBinding(\.size)) {
            ForEach(NotchHUDTileSize.allCases) { size in
              Text(size.displayName).tag(size)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
        }

        GridRow {
          compactLabel(L10n.string("Value formatting"))
          HStack(spacing: 8) {
            Picker(L10n.string("Precision"), selection: tileBinding(\.precision)) {
              ForEach(NotchHUDTilePrecision.allCases) { precision in
                Text(precision.displayName).tag(precision)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Toggle(L10n.string("Show measurement unit"), isOn: tileBinding(\.showsUnit))
              .toggleStyle(.checkbox)
          }
        }
      }

      DisclosureGroup(isExpanded: $showsTileAppearance) {
        tileAppearanceControls
          .padding(.top, 8)
      } label: {
        Label(L10n.string("Color and background"), systemImage: "paintbrush.fill")
          .font(.subheadline.weight(.semibold))
      }

      if tile.colorMode == .semantic {
        DisclosureGroup(isExpanded: $showsThresholds) {
          thresholdControls
            .padding(.top, 8)
        } label: {
          Label(L10n.string("Threshold colors"), systemImage: "gauge.with.dots.needle.67percent")
            .font(.subheadline.weight(.semibold))
        }
      }
    }
  }

  private var panelAppearanceCard: some View {
    CompactHUDCard {
      Label(L10n.string("Panel appearance"), systemImage: "rectangle.3.group.fill")
        .font(.headline)

      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
        GridRow {
          compactLabel(L10n.string("Panel density"))
          Picker(L10n.string("Density"), selection: configurationBinding(\.density)) {
            ForEach(NotchHUDDensity.allCases) { density in
              Text(density.displayName).tag(density)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
        }

        GridRow {
          compactLabel(L10n.string("Base text size"))
          Picker(L10n.string("Text size"), selection: configurationBinding(\.textSize)) {
            ForEach(NotchHUDTextSize.allCases) { size in
              Text(size.displayName).tag(size)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
        }

        GridRow {
          compactLabel(L10n.string("Panel background strength"))
          HStack(spacing: 8) {
            Slider(
              value: configurationBinding(\.backgroundOpacity),
              in: 0.2...0.95,
              step: 0.05)
            Text("\(Int(settings.notchHUDConfiguration.backgroundOpacity * 100))%")
              .font(.caption.monospacedDigit())
              .frame(width: 38, alignment: .trailing)
          }
        }
      }

      Divider()

      HStack(spacing: 18) {
        Toggle(
          L10n.string("Labels in automatic tile mode"),
          isOn: configurationBinding(\.showLabels))
        Toggle(
          L10n.string("Show separators"),
          isOn: configurationBinding(\.showSeparators))
        Toggle(
          L10n.string("Hide unavailable tiles"),
          isOn: configurationBinding(\.hideUnavailableMetrics))
      }
      .toggleStyle(.checkbox)
      .font(.caption)
    }
  }

  private var displayCard: some View {
    CompactHUDCard {
      Toggle(
        isOn: configurationBinding(\.showOnDisplaysWithoutNotch)
      ) {
        Label(L10n.string("Show on displays without a notch"), systemImage: "display.2")
          .font(.subheadline.weight(.semibold))
      }
      .toggleStyle(.switch)
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
    .padding(.horizontal, 2)
  }

  private var tileSelector: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(MenuMetric.allCases) { metric in
          Button {
            selectedMetric = metric
          } label: {
            HStack(spacing: 5) {
              Image(systemName: settings.notchHUDConfiguration.tileConfiguration(for: metric).symbolName)
              Text(metric.notchHUDShortLabel)
            }
            .font(.caption.weight(selectedMetric == metric ? .semibold : .regular))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
              selectedMetric == metric ? Color.accentColor.opacity(0.16) : Color.clear,
              in: Capsule())
            .overlay(
              Capsule()
                .stroke(
                  selectedMetric == metric ? Color.accentColor.opacity(0.42) : Color.secondary.opacity(0.18),
                  lineWidth: 1))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("notchHUDTileSelector.\(metric.rawValue)")
        }
      }
    }
  }

  private var tileAppearanceControls: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
      GridRow {
        compactLabel(L10n.string("Content alignment"))
        Picker(L10n.string("Content alignment"), selection: tileBinding(\.alignment)) {
          ForEach(NotchHUDTileAlignment.allCases) { alignment in
            Text(alignment.displayName).tag(alignment)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }

      GridRow {
        compactLabel(L10n.string("Value emphasis"))
        Picker(L10n.string("Value emphasis"), selection: tileBinding(\.emphasis)) {
          ForEach(NotchHUDTileEmphasis.allCases) { emphasis in
            Text(emphasis.displayName).tag(emphasis)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }

      GridRow {
        compactLabel(L10n.string("Value color"))
        HStack(spacing: 8) {
          Picker(L10n.string("Value color"), selection: tileBinding(\.colorMode)) {
            ForEach(NotchHUDTileColorMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)

          if tile.colorMode == .custom {
            Picker(L10n.string("Custom color"), selection: tileBinding(\.accent)) {
              ForEach(NotchHUDTileAccent.allCases) { accent in
                Text(accent.displayName).tag(accent)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
          }
        }
      }

      GridRow {
        compactLabel(L10n.string("Tile background"))
        Picker(L10n.string("Tile background"), selection: tileBinding(\.backgroundStyle)) {
          ForEach(NotchHUDTileBackgroundStyle.allCases) { style in
            Text(style.displayName).tag(style)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }

      if tile.backgroundStyle != .none {
        GridRow {
          compactLabel(L10n.string("Tile background strength"))
          HStack(spacing: 8) {
            Slider(value: tileBinding(\.backgroundOpacity), in: 0...1, step: 0.05)
            Text("\(Int(tile.backgroundOpacity * 100))%")
              .font(.caption.monospacedDigit())
              .frame(width: 38, alignment: .trailing)
          }
        }
      }
    }
  }

  private var thresholdControls: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
      GridRow {
        compactLabel(L10n.string("Threshold direction"))
        Picker(L10n.string("Threshold direction"), selection: tileBinding(\.thresholdDirection)) {
          ForEach(NotchHUDThresholdDirection.allCases) { direction in
            Text(direction.displayName).tag(direction)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
      }

      GridRow {
        compactLabel(L10n.string("Warning"))
        TextField(
          L10n.string("Warning"),
          value: tileBinding(\.warningThreshold),
          format: .number)
          .textFieldStyle(.roundedBorder)
      }

      GridRow {
        compactLabel(L10n.string("Critical"))
        TextField(
          L10n.string("Critical"),
          value: tileBinding(\.criticalThreshold),
          format: .number)
          .textFieldStyle(.roundedBorder)
      }
    }
  }

  private func panelSummary(side: NotchHUDSide) -> some View {
    let configuredMetrics = configuredMetrics(for: side)
    let visibleCount = side == .left
      ? settings.notchHUDConfiguration.leftVisibleCount
      : settings.notchHUDConfiguration.rightVisibleCount
    let enabled = side == .left
      ? settings.notchHUDConfiguration.showLeftPanel
      : settings.notchHUDConfiguration.showRightPanel

    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 7) {
        Image(systemName: side == .left ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled")
          .foregroundStyle(Color.accentColor)
        Text(side.displayName)
          .font(.subheadline.weight(.semibold))
        Spacer()
        Toggle("", isOn: panelVisibilityBinding(side: side))
          .labelsHidden()
          .toggleStyle(.switch)
      }

      HStack {
        Text(
          configuredMetrics
            .prefix(visibleCount)
            .map(\.notchHUDShortLabel)
            .joined(separator: " · "))
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer()
        Stepper(
          value: visibleCountBinding(side: side),
          in: 1...max(1, min(configuredMetrics.count, NotchHUDConfigurationPolicy.maximumMetricsPerSide))) {
            Text("\(enabled ? min(visibleCount, configuredMetrics.count) : 0)")
              .font(.caption.monospacedDigit())
              .frame(width: 18)
          }
          .disabled(configuredMetrics.isEmpty || !enabled)
          .accessibilityIdentifier("notchHUDVisibleCount.\(side.rawValue)")
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
  }

  private func compactLabel(_ title: String) -> some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .frame(width: 142, alignment: .leading)
  }

  private var presetBinding: Binding<NotchHUDPreset> {
    Binding(
      get: { settings.notchHUDPreset },
      set: { preset in
        settings.applyNotchHUDPreset(preset)
        selectedMetric = .cpu
      })
  }

  private var tile: NotchHUDTileConfiguration {
    settings.notchHUDConfiguration.tileConfiguration(for: selectedMetric)
  }

  private var placementBinding: Binding<CompactHUDPlacement> {
    Binding(
      get: {
        switch settings.notchHUDConfiguration.placement(of: selectedMetric) {
        case .left: return .left
        case .right: return .right
        case nil: return .hidden
        }
      },
      set: { settings.setNotchHUDMetric(selectedMetric, side: $0.side) })
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

  private func tileBinding<Value>(
    _ keyPath: WritableKeyPath<NotchHUDTileConfiguration, Value>
  ) -> Binding<Value> {
    Binding(
      get: { tile[keyPath: keyPath] },
      set: { newValue in
        var updated = tile
        updated[keyPath: keyPath] = newValue
        settings.notchHUDConfiguration = NotchHUDConfigurationPolicy.settingTile(
          updated,
          for: selectedMetric,
          in: settings.notchHUDConfiguration)
      })
  }

  private func panelVisibilityBinding(side: NotchHUDSide) -> Binding<Bool> {
    switch side {
    case .left: return configurationBinding(\.showLeftPanel)
    case .right: return configurationBinding(\.showRightPanel)
    }
  }

  private func visibleCountBinding(side: NotchHUDSide) -> Binding<Int> {
    switch side {
    case .left: return configurationBinding(\.leftVisibleCount)
    case .right: return configurationBinding(\.rightVisibleCount)
    }
  }

  private func configuredMetrics(for side: NotchHUDSide) -> [MenuMetric] {
    switch side {
    case .left: return settings.notchHUDConfiguration.leftMetrics
    case .right: return settings.notchHUDConfiguration.rightMetrics
    }
  }

  private func resetSelectedTile() {
    settings.notchHUDConfiguration = NotchHUDConfigurationPolicy.resettingTile(
      selectedMetric,
      in: settings.notchHUDConfiguration)
  }
}

@MainActor
private struct CompactNotchHUDPreview: View {
  let snapshot: SystemSnapshot
  let configuration: NotchHUDConfiguration

  var body: some View {
    GeometryReader { geometry in
      let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
      let leftMetrics = normalized.metrics(for: .left)
      let rightMetrics = normalized.metrics(for: .right)
      let leftWidth = normalized.showLeftPanel
        ? NotchHUDLayout.preferredPanelWidth(metrics: leftMetrics, configuration: normalized)
        : 0
      let rightWidth = normalized.showRightPanel
        ? NotchHUDLayout.preferredPanelWidth(metrics: rightMetrics, configuration: normalized)
        : 0
      let notchWidth: CGFloat = 78
      let totalWidth = leftWidth + rightWidth + notchWidth + 14
      let scale = min(1, max(0.44, (geometry.size.width - 16) / max(totalWidth, 1)))

      ZStack {
        RoundedRectangle(cornerRadius: 10)
          .fill(Color.black.opacity(0.9))

        HStack(spacing: 7) {
          if normalized.showLeftPanel {
            NotchHUDSideContentView(
              snapshot: snapshot,
              configuration: normalized,
              side: .left)
              .frame(width: leftWidth, height: CGFloat(normalized.density.panelHeight))
          }

          RoundedRectangle(cornerRadius: 8)
            .fill(Color.black)
            .frame(width: notchWidth, height: 26)
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

private struct CompactHUDCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      content
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 11))
    .overlay(
      RoundedRectangle(cornerRadius: 11)
        .stroke(.quaternary.opacity(0.38), lineWidth: 1))
  }
}
