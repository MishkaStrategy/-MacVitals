import SwiftUI

struct PowerFlowView: View {
    let snapshot: SystemSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Label("Power flow", systemImage: "bolt.horizontal.fill").font(.headline); Spacer(); statusLabel }
            HStack(spacing: 8) {
                node("Adapter", detail: ratedPower, symbol: "powerplug")
                Image(systemName: "arrow.right").accessibilityHidden(true)
                node("System", detail: systemPower, symbol: "laptopcomputer")
            }
            if let battery = snapshot.battery.value, battery.present {
                HStack(spacing: 8) {
                    node("Battery", detail: batteryPower, symbol: "battery.75percent")
                    Image(systemName: battery.batteryPowerWatts ?? 0 < 0 ? "arrow.right" : "arrow.left").accessibilityHidden(true)
                    Text(battery.batteryPowerWatts ?? 0 < 0 ? "Supporting system" : "Charging").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private func node(_ title: LocalizedStringKey, detail: String, symbol: String) -> some View {
        Label { VStack(alignment: .leading) { Text(title).font(.caption); Text(detail).font(.system(.body, design: .rounded).monospacedDigit()) } } icon: { Image(systemName: symbol) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var ratedPower: String { snapshot.adapter.value?.ratedPowerWatts.map { "Rated \(Int($0)) W" } ?? "—" }
    private var systemPower: String { snapshot.power.value?.estimatedSystemPowerWatts.map { "~\(String(format: "%.1f", $0)) W" } ?? "Not measured" }
    private var batteryPower: String { snapshot.battery.value?.batteryPowerWatts.map { "\(String(format: "%.1f", abs($0))) W" } ?? "—" }
    private var statusLabel: some View {
        let status = snapshot.power.value?.status ?? .unknown
        return Label(statusText(status), systemImage: status == .insufficient ? "exclamationmark.triangle.fill" : "checkmark.circle")
            .font(.caption.bold()).accessibilityLabel(statusText(status))
    }
    private func statusText(_ status: PowerSufficiencyStatus) -> String {
        switch status { case .sufficient: return "Sufficient"; case .insufficient: return "Insufficient"; case .borderline: return "Borderline";
        case .chargingBattery: return "Charging"; case .notConnected: return "On battery"; case .sensorConflict: return "Sensor conflict"; default: return "Unknown" }
    }
}
