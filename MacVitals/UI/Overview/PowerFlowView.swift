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
          Image(systemName: batteryFlowState.symbolName)
            .accessibilityHidden(true)
          Text(batteryFlowState.displayName)
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
    MetricNumberFormatter.ratedWatts(snapshot.adapter.value?.ratedPowerWatts) ?? "—"
  }

  private var systemPower: String {
    MetricNumberFormatter.decimalWatts(
      snapshot.power.value?.estimatedSystemPowerWatts,
      estimated: true)
      ?? L10n.string("Not measured")
  }

  private var batteryPower: String {
    MetricNumberFormatter.decimalWatts(
      snapshot.battery.value?.batteryPowerWatts,
      absolute: true)
      ?? "—"
  }

  private var batteryFlowState: BatteryPowerFlowState {
    BatteryPowerFlowState.resolve(snapshot.battery.value?.batteryPowerWatts)
  }

  private var statusLabel: some View {
    let status = snapshot.power.value?.status ?? .unknown
    return Label(status.displayName, systemImage: status.symbolName)
      .font(.caption.bold())
      .accessibilityLabel(status.displayName)
  }
}
