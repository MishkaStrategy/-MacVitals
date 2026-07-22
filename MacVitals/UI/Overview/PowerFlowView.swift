import SwiftUI

struct PowerFlowView: View {
  let snapshot: SystemSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Power flow", systemImage: "bolt.horizontal.fill")
          .font(.headline)
        Spacer()
        statusLabel
      }
      HStack(spacing: 8) {
        node("Adapter", detail: ratedPower, symbol: "powerplug")
        Image(systemName: "arrow.right")
          .accessibilityHidden(true)
        node("System", detail: systemPower, symbol: "laptopcomputer")
      }
      if let battery = snapshot.battery.value, battery.present {
        HStack(spacing: 8) {
          node("Battery", detail: batteryPower, symbol: "battery.75percent")
          Image(systemName: battery.batteryPowerWatts ?? 0 < 0 ? "arrow.right" : "arrow.left")
            .accessibilityHidden(true)
          Text(batteryFlowText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(12)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
  }

  private func node(_ title: LocalizedStringKey, detail: String, symbol: String) -> some View {
    Label {
      VStack(alignment: .leading) {
        Text(title).font(.caption)
        Text(detail).font(.system(.body, design: .rounded).monospacedDigit())
      }
    } icon: {
      Image(systemName: symbol)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var ratedPower: String {
    snapshot.adapter.value?.ratedPowerWatts.map {
      L10n.format("Rated %d W", Int($0.rounded()))
    } ?? "—"
  }

  private var systemPower: String {
    snapshot.power.value?.estimatedSystemPowerWatts.map {
      L10n.format("~%.1f W", $0)
    } ?? L10n.string("Not measured")
  }

  private var batteryPower: String {
    snapshot.battery.value?.batteryPowerWatts.map {
      L10n.format("%.1f W", abs($0))
    } ?? "—"
  }

  private var batteryFlowText: String {
    let discharging = snapshot.battery.value?.batteryPowerWatts ?? 0 < 0
    return L10n.string(discharging ? "Supporting system" : "Charging")
  }

  private var statusLabel: some View {
    let status = snapshot.power.value?.status ?? .unknown
    return Label(
      statusText(status),
      systemImage: status == .insufficient
        ? "exclamationmark.triangle.fill"
        : "checkmark.circle")
      .font(.caption.bold())
      .accessibilityLabel(statusText(status))
  }

  private func statusText(_ status: PowerSufficiencyStatus) -> String {
    switch status {
    case .sufficient: return L10n.string("Sufficient")
    case .insufficient: return L10n.string("Insufficient")
    case .borderline: return L10n.string("Borderline")
    case .chargingBattery: return L10n.string("Charging")
    case .notConnected: return L10n.string("On battery")
    case .sensorConflict: return L10n.string("Sensor conflict")
    default: return L10n.string("Unknown")
    }
  }
}
