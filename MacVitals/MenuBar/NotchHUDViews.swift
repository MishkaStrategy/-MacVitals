import Combine
import SwiftUI

@MainActor
final class NotchHUDState: ObservableObject {
  @Published var snapshot: SystemSnapshot = .empty
}

@MainActor
struct NotchHUDRailView: View {
  @ObservedObject var state: NotchHUDState

  var body: some View {
    HStack(spacing: 0) {
      metricGroup(
        metrics: [.cpu, .gpu, .memory],
        labels: ["CPU", "GPU", "RAM"],
        labeled: true)

      Spacer(minLength: 220)

      metricGroup(
        metrics: [.fans, .temperature, .battery, .systemPower],
        labels: [],
        labeled: false)
    }
    .padding(.horizontal, 4)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("experimentalNotchHUDRail")
  }

  private func metricGroup(
    metrics: [MenuMetric],
    labels: [String],
    labeled: Bool
  ) -> some View {
    HStack(spacing: labeled ? 15 : 13) {
      ForEach(Array(metrics.enumerated()), id: \.element) { index, metric in
        NotchHUDMetricView(
          metric: metric,
          label: labeled && labels.indices.contains(index) ? labels[index] : nil,
          value: value(for: metric))

        if index < metrics.count - 1 {
          Divider()
            .frame(height: 18)
            .overlay(Color.white.opacity(0.12))
        }
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 32)
    .background(.ultraThinMaterial, in: Capsule())
    .overlay(
      Capsule()
        .stroke(Color.white.opacity(0.18), lineWidth: 0.8))
  }

  private func value(for metric: MenuMetric) -> String {
    MenuBarStatusTitleRenderer.segments(
      snapshot: state.snapshot,
      metrics: [metric])
      .first?.value ?? "—"
  }
}

@MainActor
private struct NotchHUDMetricView: View {
  let metric: MenuMetric
  let label: String?
  let value: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbolName)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.92))
        .frame(width: 15)

      if let label {
        VStack(alignment: .leading, spacing: -1) {
          Text(label)
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.58))
          Text(value)
            .font(.system(size: 12.5, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
        }
      } else {
        Text(value)
          .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
          .foregroundStyle(.white)
      }
    }
    .fixedSize()
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

@MainActor
struct NotchHUDDetailView: View {
  @ObservedObject var state: NotchHUDState

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "waveform.path.ecg")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.accentColor)
          .frame(width: 22, height: 22)
          .background(Color.accentColor.opacity(0.17), in: Circle())

        Text(L10n.string("Power flow"))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white)

        Spacer()

        Image(systemName: "slider.horizontal.3")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.65))
      }

      HStack(spacing: 7) {
        energyCell(
          title: L10n.string("System"),
          value: watts(systemPowerWatts),
          symbol: "bolt",
          intensity: 0.78)
        energyCell(
          title: L10n.string("Battery"),
          value: watts(batteryPowerWatts),
          symbol: "battery.100",
          intensity: 0.18)
        energyCell(
          title: L10n.string("Adapter"),
          value: watts(adapterPowerWatts),
          symbol: "powerplug",
          intensity: 0.72)
      }

      Divider()
        .overlay(Color.white.opacity(0.10))

      HStack(spacing: 7) {
        Image(systemName: statusSymbol)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(statusColor)

        Text(L10n.string("Power status"))
          .font(.system(size: 11.5, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.80))

        Text("·")
          .foregroundStyle(Color.white.opacity(0.35))

        Text(statusText)
          .font(.system(size: 11.5, weight: .medium))
          .foregroundStyle(statusColor)

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Color.white.opacity(0.55))
      }
    }
    .padding(.horizontal, 13)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 15, style: .continuous)
        .stroke(Color.white.opacity(0.18), lineWidth: 0.8))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("experimentalNotchHUDDetail")
  }

  private func energyCell(
    title: String,
    value: String,
    symbol: String,
    intensity: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 5) {
        Image(systemName: symbol)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Color.accentColor)
        Text(title)
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.62))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }

      Text(value)
        .font(.system(size: 18, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.75)

      NotchHUDSparkline(intensity: intensity)
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        .frame(height: 13)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color.white.opacity(0.07), lineWidth: 0.7))
  }

  private var systemPowerWatts: Double? {
    state.snapshot.power.value?.estimatedSystemPowerWatts
      ?? state.snapshot.adapter.value?.measuredPowerWatts
  }

  private var batteryPowerWatts: Double? {
    state.snapshot.power.value?.batteryPowerWatts
      ?? state.snapshot.battery.value?.batteryPowerWatts
  }

  private var adapterPowerWatts: Double? {
    state.snapshot.power.value?.adapterInputPowerWatts
      ?? state.snapshot.adapter.value?.measuredPowerWatts
  }

  private func watts(_ value: Double?) -> String {
    guard let value, value.isFinite, abs(value) <= 10_000 else { return "—" }
    return L10n.format("%.1f W", abs(value))
  }

  private var statusText: String {
    switch state.snapshot.power.value?.status {
    case .sufficient, .chargingBattery, .powerAdapterOnly:
      return L10n.string("Sufficient")
    case .borderline:
      return L10n.string("Borderline")
    case .insufficient:
      return L10n.string("Insufficient")
    case .notConnected:
      return L10n.string("On battery")
    case .sensorConflict:
      return L10n.string("Sensor conflict")
    case .unknown, nil:
      return L10n.string("Unknown")
    }
  }

  private var statusColor: Color {
    switch state.snapshot.power.value?.status {
    case .sufficient, .chargingBattery, .powerAdapterOnly:
      return .green
    case .borderline:
      return .orange
    case .insufficient, .sensorConflict:
      return .red
    case .notConnected, .unknown, nil:
      return Color.white.opacity(0.62)
    }
  }

  private var statusSymbol: String {
    switch state.snapshot.power.value?.status {
    case .sufficient, .chargingBattery, .powerAdapterOnly:
      return "checkmark.circle.fill"
    case .borderline:
      return "exclamationmark.circle.fill"
    case .insufficient, .sensorConflict:
      return "exclamationmark.triangle.fill"
    case .notConnected:
      return "battery.50"
    case .unknown, nil:
      return "questionmark.circle"
    }
  }
}

private struct NotchHUDSparkline: Shape {
  let intensity: CGFloat

  func path(in rect: CGRect) -> Path {
    let normalized = min(max(intensity, 0), 1)
    let points: [CGFloat] = [0.50, 0.54, 0.45, 0.60, 0.48, 0.66, 0.44, 0.57, 0.51, 0.63, 0.49]
    var path = Path()

    for (index, point) in points.enumerated() {
      let x = rect.minX + rect.width * CGFloat(index) / CGFloat(points.count - 1)
      let variation = (point - 0.5) * normalized
      let y = rect.midY - variation * rect.height * 2
      if index == 0 {
        path.move(to: CGPoint(x: x, y: y))
      } else {
        path.addLine(to: CGPoint(x: x, y: y))
      }
    }

    return path
  }
}
