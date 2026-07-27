import SwiftUI

struct PowerFlowView: View {
  let snapshot: SystemSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("Power", systemImage: "bolt.fill")
          .font(.headline)
        Spacer()
        statusLabel
      }

      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("System draw")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(systemPower)
            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
            .contentTransition(.numericText())
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text(powerSourceTitle)
            .font(.caption.bold())
          Text(powerSourceDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
      }

      Divider()

      HStack(spacing: 12) {
        secondaryMetric("Adapter", value: ratedPower, symbol: "powerplug")
        if let battery = snapshot.battery.value, battery.present {
          secondaryMetric("Battery", value: batteryPower, symbol: "battery.75percent")
        }
      }
    }
    .padding(12)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("System power")
    .accessibilityValue(systemPower)
  }

  private func secondaryMetric(
    _ title: LocalizedStringKey,
    value: String,
    symbol: String
  ) -> some View {
    Label {
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.caption2).foregroundStyle(.secondary)
        Text(value).font(.caption.monospacedDigit())
      }
    } icon: {
      Image(systemName: symbol)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var resolvedSystemPowerWatts: Double? {
    if let value = snapshot.power.value?.estimatedSystemPowerWatts,
      value.isFinite,
      value >= 0
    {
      return value
    }
    guard let battery = snapshot.battery.value,
      battery.present,
      !battery.externalPowerConnected,
      battery.state == .discharging,
      let batteryPower = battery.batteryPowerWatts,
      batteryPower.isFinite,
      abs(batteryPower) > 0.01
    else { return nil }
    return abs(batteryPower)
  }

  private var systemPower: String {
    MetricNumberFormatter.decimalWatts(
      resolvedSystemPowerWatts,
      estimated: resolvedSystemPowerWatts != nil)
      ?? "— W"
  }

  private var ratedPower: String {
    MetricNumberFormatter.ratedWatts(snapshot.adapter.value?.ratedPowerWatts) ?? "—"
  }

  private var batteryPower: String {
    MetricNumberFormatter.decimalWatts(
      snapshot.battery.value?.batteryPowerWatts,
      absolute: true)
      ?? "—"
  }

  private var powerSourceTitle: String {
    guard let battery = snapshot.battery.value else {
      return L10n.string("Sensor unavailable")
    }
    if battery.externalPowerConnected {
      return L10n.string("On adapter")
    }
    return L10n.string("On battery")
  }

  private var powerSourceDetail: String {
    if resolvedSystemPowerWatts != nil {
      return L10n.string("Live estimate from battery voltage and current")
    }
    if snapshot.battery.value?.externalPowerConnected == true {
      return L10n.string("Exact total draw is not exposed by the public adapter sensor")
    }
    return L10n.string("Waiting for battery voltage and current")
  }

  private var statusLabel: some View {
    let status = snapshot.power.value?.status ?? .unknown
    return Label(status.displayName, systemImage: status.symbolName)
      .font(.caption.bold())
      .accessibilityLabel(status.displayName)
  }
}
