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
        NotchHUDCompactMetricView(
          metric: metric,
          label: label(for: metric),
          value: value(for: metric),
          configuration: configuration)

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
    let rendered = value(for: metric).trimmingCharacters(in: .whitespacesAndNewlines)
    return rendered != "—"
      && rendered != "-"
      && !rendered.localizedCaseInsensitiveContains("unavailable")
  }

  private func label(for metric: MenuMetric) -> String? {
    guard configuration.showLabels else { return nil }
    switch metric {
    case .cpu: return "CPU"
    case .gpu: return "GPU"
    case .memory: return "RAM"
    case .temperature: return "TEMP"
    case .battery: return "BAT"
    case .fans: return "FAN"
    case .systemPower: return "PWR"
    case .adapterPower: return "AC"
    case .powerStatus: return "LOAD"
    }
  }

  private func value(for metric: MenuMetric) -> String {
    MenuBarStatusTitleRenderer.segments(
      snapshot: snapshot,
      metrics: [metric])
      .first?.value ?? "—"
  }
}

@MainActor
private struct NotchHUDCompactMetricView: View {
  let metric: MenuMetric
  let label: String?
  let value: String
  let configuration: NotchHUDConfiguration

  var body: some View {
    HStack(spacing: metricSpacing) {
      Image(systemName: symbolName)
        .font(.system(size: iconSize, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.90))
        .frame(width: iconFrameWidth)

      if let label {
        Text(label)
          .font(.system(size: labelSize, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.58))
      }

      Text(value)
        .font(.system(size: valueSize, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
    }
    .fixedSize(horizontal: label == nil, vertical: true)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label ?? metric.displayName)
    .accessibilityValue(value)
  }

  private var scale: CGFloat { CGFloat(configuration.textSize.scale) }
  private var iconSize: CGFloat { 10.5 * scale }
  private var labelSize: CGFloat { 8.5 * scale }
  private var valueSize: CGFloat { 10.5 * scale }
  private var iconFrameWidth: CGFloat { 13 * scale }
  private var metricSpacing: CGFloat {
    configuration.density == .compact ? 3 : 4
  }

  private var symbolName: String {
    switch metric {
    case .cpu: return "cpu"
    case .gpu: return "display"
    case .memory: return "memorychip"
    case .temperature: return "thermometer.medium"
    case .battery: return "battery.100"
    case .fans: return "fan"
    case .systemPower: return "bolt"
    case .adapterPower: return "powerplug"
    case .powerStatus: return "gauge.with.dots.needle.50percent"
    }
  }
}
