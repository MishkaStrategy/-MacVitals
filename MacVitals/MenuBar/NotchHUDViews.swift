import Combine
import Foundation
import SwiftUI

nonisolated enum NotchIndicatorLevel: Equatable, Sendable {
  case unavailable
  case normal
  case warning
  case critical
}

nonisolated struct NotchHUDReading: Equatable, Sendable {
  let metric: MenuMetric
  let numericValue: Double?
  let displayValue: String
  let progress: Double
  let level: NotchIndicatorLevel
}

nonisolated enum NotchHUDReadingResolver {
  static func resolve(
    snapshot: SystemSnapshot,
    configuration: NotchHUDConfiguration
  ) -> NotchHUDReading {
    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    let value = numericValue(for: normalized.metric, snapshot: snapshot)
    let displayValue = renderedValue(for: normalized.metric, value: value)
    let progress = value.map { normalizedProgress($0, metric: normalized.metric) } ?? 0
    let level = level(for: value, configuration: normalized)
    return NotchHUDReading(
      metric: normalized.metric,
      numericValue: value,
      displayValue: displayValue,
      progress: progress,
      level: level)
  }

  private static func numericValue(
    for metric: MenuMetric,
    snapshot: SystemSnapshot
  ) -> Double? {
    switch metric {
    case .cpu:
      return finite(snapshot.cpu.value?.total)
    case .gpu:
      return finite(snapshot.gpu.value?.systemUtilizationPercent)
    case .memory:
      return finite(snapshot.memory.value?.usedPercent)
    case .temperature:
      return finite(
        snapshot.temperature.value?.processorCelsius
          ?? snapshot.temperature.value?.batteryCelsius)
    case .battery:
      return finite(snapshot.battery.value?.percentage)
    case .fans:
      return snapshot.fans.value?.fans.compactMap { finite($0.currentRPM) }.max()
    case .systemPower:
      return finite(snapshot.power.value?.estimatedSystemPowerWatts).map { abs($0) }
    case .adapterPower:
      return finite(
        snapshot.power.value?.adapterInputPowerWatts
          ?? snapshot.adapter.value?.ratedPowerWatts
      ).map { abs($0) }
    case .powerStatus:
      return nil
    }
  }

  private static func renderedValue(for metric: MenuMetric, value: Double?) -> String {
    guard let value else { return "—" }

    switch metric {
    case .cpu, .gpu, .memory, .battery:
      return "\(Int(value.rounded()))%"
    case .temperature:
      return "\(Int(value.rounded()))°C"
    case .fans:
      return "\(Int(value.rounded())) RPM"
    case .systemPower, .adapterPower:
      return String(format: "%.1f W", value)
    case .powerStatus:
      return "—"
    }
  }

  private static func normalizedProgress(_ value: Double, metric: MenuMetric) -> Double {
    let range = metric.notchIndicatorRange
    guard range.upperBound > range.lowerBound else { return 0 }
    return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
  }

  private static func level(
    for value: Double?,
    configuration: NotchHUDConfiguration
  ) -> NotchIndicatorLevel {
    guard let value else { return .unavailable }

    if configuration.metric.notchIndicatorLowerIsWorse {
      if value <= configuration.criticalThreshold { return .critical }
      if value <= configuration.warningThreshold { return .warning }
    } else {
      if value >= configuration.criticalThreshold { return .critical }
      if value >= configuration.warningThreshold { return .warning }
    }
    return .normal
  }

  private static func finite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
  }
}

@MainActor
final class NotchHUDState: ObservableObject {
  @Published var snapshot: SystemSnapshot = .empty
  @Published var configuration: NotchHUDConfiguration = .minimal
  @Published var safeAreaTop: CGFloat = NotchHUDLayout.minimumSafeAreaTop
}

@MainActor
struct NotchHUDIndicatorView: View {
  @ObservedObject var state: NotchHUDState

  var body: some View {
    NotchHUDIndicatorContentView(
      snapshot: state.snapshot,
      configuration: state.configuration,
      safeAreaTop: state.safeAreaTop)
  }
}

@MainActor
struct NotchHUDIndicatorContentView: View {
  let snapshot: SystemSnapshot
  let configuration: NotchHUDConfiguration
  let safeAreaTop: CGFloat

  var body: some View {
    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    let reading = NotchHUDReadingResolver.resolve(
      snapshot: snapshot,
      configuration: normalized)
    let activeColor = indicatorColor(reading: reading, configuration: normalized)

    GeometryReader { proxy in
      let geometry = NotchHUDLayout.contourGeometry(
        in: proxy.size,
        safeAreaTop: safeAreaTop)
      let shape = NotchHUDContourShape(geometry: geometry)
      let lineWidth = CGFloat(normalized.lineThickness)

      ZStack(alignment: .top) {
        shape
          .stroke(
            Color.white.opacity(normalized.trackOpacity),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        shape
          .trim(from: 0, to: reading.progress)
          .stroke(
            activeColor,
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
          )
          .shadow(
            color: activeColor.opacity(0.75 * normalized.glowIntensity),
            radius: 2 + 6 * normalized.glowIntensity
          )
          .animation(
            normalized.animateChanges ? .easeOut(duration: 0.35) : nil,
            value: reading.progress)

        if normalized.showValueText {
          HStack(spacing: 5) {
            if normalized.showSensorName {
              Text(normalized.metric.displayName)
                .foregroundStyle(Color.white.opacity(0.82))
            }
            Text(reading.displayValue)
              .foregroundStyle(activeColor)
              .fontWeight(.semibold)
          }
          .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
          .lineLimit(1)
          .position(
            x: proxy.size.width / 2,
            y: geometry.bottomY + 16)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(normalized.metric.displayName)
      .accessibilityValue(reading.displayValue)
      .accessibilityIdentifier("experimentalNotchHUDIndicator")
    }
  }

  private func indicatorColor(
    reading: NotchHUDReading,
    configuration: NotchHUDConfiguration
  ) -> Color {
    switch configuration.colorMode {
    case .accent:
      return .accentColor
    case .custom:
      return configuration.accent.color
    case .automatic:
      switch reading.level {
      case .critical:
        return .red
      case .warning:
        return .orange
      case .unavailable:
        return Color.white.opacity(0.42)
      case .normal:
        return configuration.metric.defaultNotchIndicatorColor
      }
    }
  }
}

private struct NotchHUDContourShape: Shape {
  let geometry: NotchHUDContourGeometry

  func path(in rect: CGRect) -> Path {
    let leftShoulderStart = geometry.notchLeftX - geometry.shoulderRadius
    let leftBottomEnd = geometry.notchLeftX + geometry.shoulderRadius
    let rightBottomStart = geometry.notchRightX - geometry.shoulderRadius
    let rightShoulderEnd = geometry.notchRightX + geometry.shoulderRadius

    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: geometry.topY))
    path.addLine(to: CGPoint(x: leftShoulderStart, y: geometry.topY))
    path.addCurve(
      to: CGPoint(x: leftBottomEnd, y: geometry.bottomY),
      control1: CGPoint(x: geometry.notchLeftX, y: geometry.topY),
      control2: CGPoint(x: geometry.notchLeftX, y: geometry.bottomY))
    path.addLine(to: CGPoint(x: rightBottomStart, y: geometry.bottomY))
    path.addCurve(
      to: CGPoint(x: rightShoulderEnd, y: geometry.topY),
      control1: CGPoint(x: geometry.notchRightX, y: geometry.bottomY),
      control2: CGPoint(x: geometry.notchRightX, y: geometry.topY))
    path.addLine(to: CGPoint(x: rect.maxX, y: geometry.topY))
    return path
  }
}

extension MenuMetric {
  fileprivate var defaultNotchIndicatorColor: Color {
    switch self {
    case .battery:
      return .mint
    case .temperature:
      return .cyan
    case .systemPower, .adapterPower:
      return .green
    case .fans:
      return .blue
    case .cpu, .gpu, .memory, .powerStatus:
      return .cyan
    }
  }
}

extension NotchIndicatorAccent {
  fileprivate var color: Color {
    switch self {
    case .blue: return .blue
    case .cyan: return .cyan
    case .mint: return .mint
    case .green: return .green
    case .yellow: return .yellow
    case .orange: return .orange
    case .red: return .red
    case .pink: return .pink
    case .purple: return .purple
    case .white: return .white
    }
  }
}
