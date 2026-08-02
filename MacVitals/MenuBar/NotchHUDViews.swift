import Combine
import SwiftUI

@MainActor
final class NotchHUDState: ObservableObject {
  @Published var snapshot: SystemSnapshot = .empty
}

nonisolated enum NotchHUDSide: Sendable, Equatable {
  case left
  case right
}

@MainActor
struct NotchHUDSideView: View {
  @ObservedObject var state: NotchHUDState
  let side: NotchHUDSide

  var body: some View {
    HStack(spacing: 8) {
      ForEach(Array(metrics.enumerated()), id: \.element) { index, metric in
        NotchHUDCompactMetricView(
          metric: metric,
          label: label(for: metric),
          value: value(for: metric))

        if index < metrics.count - 1 {
          Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 14)
        }
      }
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(
      Capsule()
        .stroke(Color.white.opacity(0.18), lineWidth: 0.7))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(
      side == .left ? "experimentalNotchHUDLeft" : "experimentalNotchHUDRight")
  }

  private var metrics: [MenuMetric] {
    switch side {
    case .left:
      return [.cpu, .gpu, .memory]
    case .right:
      return [.fans, .temperature, .battery, .systemPower]
    }
  }

  private func label(for metric: MenuMetric) -> String? {
    switch metric {
    case .cpu: return "CPU"
    case .gpu: return "GPU"
    case .memory: return "RAM"
    default: return nil
    }
  }

  private func value(for metric: MenuMetric) -> String {
    MenuBarStatusTitleRenderer.segments(
      snapshot: state.snapshot,
      metrics: [metric])
      .first?.value ?? "—"
  }
}

@MainActor
private struct NotchHUDCompactMetricView: View {
  let metric: MenuMetric
  let label: String?
  let value: String

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: symbolName)
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.90))
        .frame(width: 13)

      if let label {
        Text(label)
          .font(.system(size: 8.5, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.58))
      }

      Text(value)
        .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
    .fixedSize(horizontal: label == nil, vertical: true)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label ?? metric.displayName)
    .accessibilityValue(value)
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
