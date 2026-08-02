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

nonisolated struct NotchHUDIndicatorSegmentRange: Equatable, Sendable {
  let from: CGFloat
  let to: CGFloat
}

nonisolated enum NotchHUDIndicatorSegments {
  private static let splitGap: CGFloat = 0.008

  static func primary(
    progress: Double,
    count: NotchIndicatorCount
  ) -> NotchHUDIndicatorSegmentRange {
    let resolvedProgress = CGFloat(min(max(progress, 0), 1))
    guard count == .two else {
      return NotchHUDIndicatorSegmentRange(from: 0, to: resolvedProgress)
    }

    let splitStart = 0.5 - splitGap
    return NotchHUDIndicatorSegmentRange(
      from: splitStart * (1 - resolvedProgress),
      to: splitStart)
  }

  static func secondary(progress: Double) -> NotchHUDIndicatorSegmentRange {
    let resolvedProgress = CGFloat(min(max(progress, 0), 1))
    let splitEnd = 0.5 + splitGap
    return NotchHUDIndicatorSegmentRange(
      from: splitEnd,
      to: splitEnd + (1 - splitEnd) * resolvedProgress)
  }

  static func primaryTrack(count: NotchIndicatorCount) -> NotchHUDIndicatorSegmentRange {
    guard count == .two else {
      return NotchHUDIndicatorSegmentRange(from: 0, to: 1)
    }
    return NotchHUDIndicatorSegmentRange(from: 0, to: 0.5 - splitGap)
  }

  static let secondaryTrack = NotchHUDIndicatorSegmentRange(
    from: 0.5 + splitGap,
    to: 1)
}

nonisolated enum NotchHUDReadingResolver {
  static func resolve(
    snapshot: SystemSnapshot,
    configuration: NotchHUDConfiguration
  ) -> NotchHUDReading {
    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    return resolve(
      snapshot: snapshot,
      metric: normalized.metric,
      warningThreshold: normalized.warningThreshold,
      criticalThreshold: normalized.criticalThreshold)
  }

  static func resolve(
    snapshot: SystemSnapshot,
    metric: MenuMetric,
    warningThreshold: Double,
    criticalThreshold: Double
  ) -> NotchHUDReading {
    let value = numericValue(for: metric, snapshot: snapshot)
    let displayValue = renderedValue(for: metric, value: value)
    let progress = value.map { normalizedProgress($0, metric: metric) } ?? 0
    let level = level(
      for: value,
      metric: metric,
      warningThreshold: warningThreshold,
      criticalThreshold: criticalThreshold)
    return NotchHUDReading(
      metric: metric,
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
    metric: MenuMetric,
    warningThreshold: Double,
    criticalThreshold: Double
  ) -> NotchIndicatorLevel {
    guard let value else { return .unavailable }

    if metric.notchIndicatorLowerIsWorse {
      if value <= criticalThreshold { return .critical }
      if value <= warningThreshold { return .warning }
    } else {
      if value >= criticalThreshold { return .critical }
      if value >= warningThreshold { return .warning }
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
    let primaryReading = NotchHUDReadingResolver.resolve(
      snapshot: snapshot,
      configuration: normalized)
    let secondaryReading = resolvedSecondaryReading(
      snapshot: snapshot,
      configuration: normalized)
    let primaryColor = indicatorColor(
      reading: primaryReading,
      configuration: normalized)
    let secondaryColor = secondaryReading.map {
      indicatorColor(reading: $0, configuration: normalized)
    }

    GeometryReader { proxy in
      let geometry = NotchHUDLayout.contourGeometry(
        in: proxy.size,
        safeAreaTop: safeAreaTop)
      let shape = NotchHUDContourShape(geometry: geometry)
      let lineWidth = CGFloat(normalized.lineThickness)
      let count = normalized.indicatorCount
      let primaryTrack = NotchHUDIndicatorSegments.primaryTrack(count: count)
      let primarySegment = NotchHUDIndicatorSegments.primary(
        progress: primaryReading.progress,
        count: count)

      ZStack(alignment: .top) {
        shape
          .trim(from: primaryTrack.from, to: primaryTrack.to)
          .stroke(
            Color.white.opacity(normalized.trackOpacity),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        shape
          .trim(from: primarySegment.from, to: primarySegment.to)
          .stroke(
            primaryColor,
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
          )
          .shadow(
            color: primaryColor.opacity(0.75 * normalized.glowIntensity),
            radius: 2 + 6 * normalized.glowIntensity
          )
          .animation(
            normalized.animateChanges ? .easeOut(duration: 0.35) : nil,
            value: primaryReading.progress)

        if let secondaryReading, let secondaryColor {
          let secondaryTrack = NotchHUDIndicatorSegments.secondaryTrack
          let secondarySegment = NotchHUDIndicatorSegments.secondary(
            progress: secondaryReading.progress)

          shape
            .trim(from: secondaryTrack.from, to: secondaryTrack.to)
            .stroke(
              Color.white.opacity(normalized.trackOpacity),
              style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

          shape
            .trim(from: secondarySegment.from, to: secondarySegment.to)
            .stroke(
              secondaryColor,
              style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
            .shadow(
              color: secondaryColor.opacity(0.75 * normalized.glowIntensity),
              radius: 2 + 6 * normalized.glowIntensity
            )
            .animation(
              normalized.animateChanges ? .easeOut(duration: 0.35) : nil,
              value: secondaryReading.progress)
        }

        if normalized.showValueText {
          if let secondaryReading, let secondaryColor {
            HStack(spacing: 24) {
              indicatorLabel(
                reading: primaryReading,
                color: primaryColor,
                showSensorName: normalized.showSensorName)
                .frame(maxWidth: .infinity, alignment: .trailing)

              indicatorLabel(
                reading: secondaryReading,
                color: secondaryColor,
                showSensorName: normalized.showSensorName)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: max(proxy.size.width - 44, 160))
            .position(
              x: proxy.size.width / 2,
              y: geometry.bottomY + 12)
          } else {
            indicatorLabel(
              reading: primaryReading,
              color: primaryColor,
              showSensorName: normalized.showSensorName)
              .position(
                x: proxy.size.width / 2,
                y: geometry.bottomY + 12)
          }
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabel(
        primary: primaryReading,
        secondary: secondaryReading))
      .accessibilityValue(accessibilityValue(
        primary: primaryReading,
        secondary: secondaryReading))
      .accessibilityIdentifier("experimentalNotchHUDIndicator")
    }
  }

  private func resolvedSecondaryReading(
    snapshot: SystemSnapshot,
    configuration: NotchHUDConfiguration
  ) -> NotchHUDReading? {
    guard let metric = configuration.secondaryMetric else { return nil }
    let defaults = metric.notchIndicatorDefaultThresholds
    return NotchHUDReadingResolver.resolve(
      snapshot: snapshot,
      metric: metric,
      warningThreshold: configuration.secondaryWarningThreshold ?? defaults.warning,
      criticalThreshold: configuration.secondaryCriticalThreshold ?? defaults.critical)
  }

  private func indicatorLabel(
    reading: NotchHUDReading,
    color: Color,
    showSensorName: Bool
  ) -> some View {
    HStack(spacing: 5) {
      if showSensorName {
        Text(reading.metric.displayName)
          .foregroundStyle(Color.white.opacity(0.82))
      }
      Text(reading.displayValue)
        .foregroundStyle(color)
        .fontWeight(.semibold)
    }
    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
    .lineLimit(1)
    .minimumScaleFactor(0.72)
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
        return reading.metric.defaultNotchIndicatorColor
      }
    }
  }

  private func accessibilityLabel(
    primary: NotchHUDReading,
    secondary: NotchHUDReading?
  ) -> String {
    guard let secondary else { return primary.metric.displayName }
    return "\(primary.metric.displayName), \(secondary.metric.displayName)"
  }

  private func accessibilityValue(
    primary: NotchHUDReading,
    secondary: NotchHUDReading?
  ) -> String {
    guard let secondary else { return primary.displayValue }
    return "\(primary.displayValue), \(secondary.displayValue)"
  }
}

private struct NotchHUDContourShape: Shape {
  let geometry: NotchHUDContourGeometry

  func path(in rect: CGRect) -> Path {
    let leftX = min(max(geometry.notchLeftX, rect.minX), rect.maxX)
    let rightX = min(max(geometry.notchRightX, leftX), rect.maxX)
    let topY = min(max(geometry.topY, rect.minY), rect.maxY)
    let bottomY = min(max(geometry.bottomY, topY), rect.maxY)
    let radius = min(
      geometry.shoulderRadius,
      max(0, (rightX - leftX) / 2),
      max(0, bottomY - topY))

    var path = Path()
    path.move(to: CGPoint(x: leftX, y: topY))
    path.addLine(to: CGPoint(x: leftX, y: bottomY - radius))
    path.addQuadCurve(
      to: CGPoint(x: leftX + radius, y: bottomY),
      control: CGPoint(x: leftX, y: bottomY))
    path.addLine(to: CGPoint(x: rightX - radius, y: bottomY))
    path.addQuadCurve(
      to: CGPoint(x: rightX, y: bottomY - radius),
      control: CGPoint(x: rightX, y: bottomY))
    path.addLine(to: CGPoint(x: rightX, y: topY))
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
