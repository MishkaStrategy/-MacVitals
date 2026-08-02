import Combine
import SwiftUI

@MainActor
final class NotchHUDState: ObservableObject {
  @Published var snapshot: SystemSnapshot = .empty
  @Published var configuration: NotchHUDConfiguration = .balanced
}

@MainActor
struct NotchHUDSideView: View {
  @ObservedObject var state: NotchHUDState
  @ObservedObject var caffeinate: CaffeinateController
  let side: NotchHUDSide

  var body: some View {
    NotchHUDSideContentView(
      snapshot: state.snapshot,
      configuration: state.configuration,
      side: side,
      isCaffeinateActive: caffeinate.isActive,
      onToggleCaffeinate: caffeinate.toggle)
  }
}

@MainActor
struct NotchHUDSideContentView: View {
  let snapshot: SystemSnapshot
  let configuration: NotchHUDConfiguration
  let side: NotchHUDSide
  var isCaffeinateActive = false
  var onToggleCaffeinate: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: CGFloat(configuration.density.itemSpacing)) {
      ForEach(Array(metrics.enumerated()), id: \.element) { index, metric in
        let tile = configuration.tileConfiguration(for: metric)
        NotchHUDCompactMetricView(
          metric: metric,
          rawValue: rawValue(for: metric),
          configuration: configuration,
          tileConfiguration: tile)

        if configuration.showSeparators, index < metrics.count - 1 {
          Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: separatorHeight)
        }
      }

      if showsCaffeinateButton {
        caffeinateButton
      }
    }
    .padding(.horizontal, CGFloat(configuration.density.horizontalPadding))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.ultraThinMaterial, in: Capsule())
    .background(
      Color.black.opacity(configuration.backgroundOpacity * 0.55),
      in: Capsule())
    .overlay(
      Capsule()
        .stroke(Color.white.opacity(0.14 + configuration.backgroundOpacity * 0.08), lineWidth: 0.7))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(
      side == .left ? "experimentalNotchHUDLeft" : "experimentalNotchHUDRight")
  }

  private var configuredMetrics: [MenuMetric] {
    NotchHUDConfigurationPolicy.normalized(configuration).metrics(for: side)
  }

  private var metrics: [MenuMetric] {
    guard configuration.hideUnavailableMetrics else { return configuredMetrics }
    let available = configuredMetrics.filter { isAvailable($0) }
    return available.isEmpty ? Array(configuredMetrics.prefix(1)) : available
  }

  private var showsCaffeinateButton: Bool {
    guard onToggleCaffeinate != nil else { return false }
    return NotchHUDLayout.caffeinateButtonSide(in: configuration) == side
  }

  private var caffeinateButton: some View {
    let diameter = NotchHUDLayout.caffeinateButtonDiameter(configuration: configuration)
    let actionTitle = isCaffeinateActive ? "Allow Mac to sleep" : "Keep Mac awake"
    let stateTitle = isCaffeinateActive ? "Awake mode is on" : "Awake mode is off"

    return Button {
      onToggleCaffeinate?()
    } label: {
      Image(systemName: "cup.and.saucer.fill")
        .font(.system(size: diameter * 0.47, weight: .semibold))
        .foregroundStyle(isCaffeinateActive ? Color.white : Color.white.opacity(0.88))
        .frame(width: diameter, height: diameter)
        .background(
          isCaffeinateActive ? Color.accentColor : Color.white.opacity(0.12),
          in: Circle())
        .overlay(
          Circle()
            .stroke(
              isCaffeinateActive ? Color.white.opacity(0.34) : Color.white.opacity(0.18),
              lineWidth: 0.7))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(L10n.string(actionTitle))
    .accessibilityLabel(L10n.string(actionTitle))
    .accessibilityValue(L10n.string(stateTitle))
    .accessibilityIdentifier("notchHUDCaffeinateButton")
  }

  private var separatorHeight: CGFloat {
    CGFloat(configuration.density.panelHeight * 0.5)
  }

  private func isAvailable(_ metric: MenuMetric) -> Bool {
    let rendered = rawValue(for: metric).trimmingCharacters(in: .whitespacesAndNewlines)
    return rendered != "—"
      && rendered != "-"
      && !rendered.localizedCaseInsensitiveContains("unavailable")
  }

  private func rawValue(for metric: MenuMetric) -> String {
    MenuBarStatusTitleRenderer.segments(
      snapshot: snapshot,
      metrics: [metric])
      .first?.value ?? "—"
  }
}

@MainActor
private struct NotchHUDCompactMetricView: View {
  let metric: MenuMetric
  let rawValue: String
  let configuration: NotchHUDConfiguration
  let tileConfiguration: NotchHUDTileConfiguration

  var body: some View {
    HStack(spacing: metricSpacing) {
      if showsIcon {
        Image(systemName: tileConfiguration.symbolName)
          .font(.system(size: iconSize, weight: .semibold))
          .foregroundStyle(foregroundColor.opacity(0.92))
          .frame(width: iconFrameWidth)
      }

      if showsLabel {
        Text(label)
          .font(.system(size: labelSize, weight: .semibold))
          .foregroundStyle(foregroundColor.opacity(0.62))
          .lineLimit(1)
      }

      Text(value)
        .font(
          .system(
            size: valueSize,
            weight: valueWeight,
            design: .rounded)
            .monospacedDigit())
        .foregroundStyle(foregroundColor)
        .lineLimit(1)
        .minimumScaleFactor(0.62)
    }
    .padding(.horizontal, tileHorizontalPadding)
    .frame(
      width: NotchHUDLayout.preferredTileWidth(metric: metric, configuration: configuration),
      maxHeight: .infinity,
      alignment: frameAlignment)
    .background(
      RoundedRectangle(cornerRadius: tileCornerRadius)
        .fill(backgroundColor))
    .overlay(
      RoundedRectangle(cornerRadius: tileCornerRadius)
        .stroke(outlineColor, lineWidth: tileConfiguration.backgroundStyle == .outline ? 0.8 : 0))
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(value)
    .accessibilityIdentifier("notchHUDTile.\(metric.rawValue)")
  }

  private var value: String {
    NotchHUDTileValueFormatter.renderedValue(
      from: rawValue,
      configuration: tileConfiguration)
  }

  private var label: String {
    tileConfiguration.customLabel.isEmpty
      ? metric.notchHUDShortLabel
      : tileConfiguration.customLabel
  }

  private var showsIcon: Bool {
    tileConfiguration.contentStyle.showsIcon(globalShowsLabels: configuration.showLabels)
  }

  private var showsLabel: Bool {
    tileConfiguration.contentStyle.showsLabel(globalShowsLabels: configuration.showLabels)
  }

  private var scale: CGFloat {
    CGFloat(configuration.textSize.scale * tileConfiguration.emphasis.scale)
  }

  private var iconSize: CGFloat { 10.5 * scale }
  private var labelSize: CGFloat { 8.5 * CGFloat(configuration.textSize.scale) }
  private var valueSize: CGFloat { 10.5 * scale }
  private var iconFrameWidth: CGFloat { 13 * scale }
  private var metricSpacing: CGFloat { configuration.density == .compact ? 3 : 4 }
  private var tileCornerRadius: CGFloat { max(5, CGFloat(configuration.density.panelHeight) * 0.28) }
  private var tileHorizontalPadding: CGFloat {
    tileConfiguration.backgroundStyle == .none ? 0 : 4
  }

  private var valueWeight: Font.Weight {
    switch tileConfiguration.emphasis {
    case .muted: return .medium
    case .normal: return .semibold
    case .prominent: return .bold
    }
  }

  private var frameAlignment: Alignment {
    switch tileConfiguration.alignment {
    case .leading: return .leading
    case .center: return .center
    case .trailing: return .trailing
    }
  }

  private var foregroundColor: Color {
    switch tileConfiguration.colorMode {
    case .inherited, .monochrome:
      return .white
    case .accent:
      return .accentColor
    case .custom:
      return tileConfiguration.accent.color
    case .semantic:
      switch NotchHUDTileConfigurationPolicy.semanticState(
        renderedValue: rawValue,
        configuration: tileConfiguration)
      {
      case .normal: return .green
      case .warning: return .orange
      case .critical: return .red
      case .unavailable: return Color.white.opacity(0.45)
      }
    }
  }

  private var backgroundColor: Color {
    switch tileConfiguration.backgroundStyle {
    case .none, .outline:
      return .clear
    case .subtle:
      return foregroundColor.opacity(tileConfiguration.backgroundOpacity * 0.45)
    case .filled:
      return foregroundColor.opacity(tileConfiguration.backgroundOpacity)
    }
  }

  private var outlineColor: Color {
    tileConfiguration.backgroundStyle == .outline
      ? foregroundColor.opacity(max(0.18, tileConfiguration.backgroundOpacity))
      : .clear
  }
}

private extension NotchHUDTileAccent {
  var color: Color {
    switch self {
    case .white: return .white
    case .blue: return .blue
    case .cyan: return .cyan
    case .green: return .green
    case .yellow: return .yellow
    case .orange: return .orange
    case .red: return .red
    case .pink: return .pink
    case .purple: return .purple
    }
  }
}
