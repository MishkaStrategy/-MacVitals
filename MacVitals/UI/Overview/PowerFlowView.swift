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
          Text("System")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(systemPower)
            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
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
    .accessibilityLabel("Power")
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
    guard let value = snapshot.power.value?.estimatedSystemPowerWatts,
      value.isFinite,
      value >= 0
    else { return nil }
    return value
  }

  private var systemPower: String {
    MetricNumberFormatter.decimalWatts(
      resolvedSystemPowerWatts,
      estimated: snapshot.power.isEstimated)
      ?? L10n.string("Not measured")
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
      return L10n.string("Unknown")
    }
    if battery.externalPowerConnected {
      return L10n.string("Adapter")
    }
    return L10n.string("On battery")
  }

  private var powerSourceDetail: String {
    if resolvedSystemPowerWatts != nil {
      return snapshot.power.isEstimated
        ? L10n.string("Estimated")
        : L10n.string("IOKit registry")
    }
    return L10n.string("Collecting data")
  }

  private var statusLabel: some View {
    let status = snapshot.power.value?.status ?? .unknown
    return Label(status.displayName, systemImage: status.symbolName)
      .font(.caption.bold())
      .accessibilityLabel(status.displayName)
  }
}
