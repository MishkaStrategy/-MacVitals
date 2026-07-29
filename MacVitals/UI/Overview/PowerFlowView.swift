import SwiftUI

struct PowerFlowView: View {
  @Environment(\.appTheme) private var theme
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  let snapshot: SystemSnapshot
  var onOpen: (() -> Void)?

  init(snapshot: SystemSnapshot, onOpen: (() -> Void)? = nil) {
    self.snapshot = snapshot
    self.onOpen = onOpen
  }

  var body: some View {
    let accent = theme.color(for: .systemPower)
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Label("Power flow", systemImage: "bolt.horizontal.circle.fill")
          .font(.headline)
          .foregroundStyle(accent)
        Spacer()
        statusBadge
        if onOpen != nil {
          Image(systemName: "chevron.right")
            .font(.caption.bold())
            .foregroundStyle(.tertiary)
        }
      }

      HStack(spacing: 10) {
        powerTile(
          title: L10n.string("System consumption"),
          value: systemPower,
          detail: systemPowerDetail,
          symbol: "laptopcomputer.and.arrow.down",
          metric: .systemPower)
        powerTile(
          title: L10n.string("Battery flow"),
          value: batteryPower,
          detail: batteryFlowState.displayName,
          symbol: batteryFlowState.symbolName,
          metric: .battery)
        powerTile(
          title: L10n.string("Adapter input"),
          value: adapterInputPower,
          detail: adapterDetail,
          symbol: "powerplug.fill",
          metric: .systemPower)
      }

      HStack(spacing: 8) {
        sourceBadge
        Spacer()
        Label(powerSourceTitle, systemImage: powerSourceSymbol)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(13)
    .background(
      reduceTransparency
        ? Color(nsColor: .controlBackgroundColor)
        : accent.opacity(theme.style == .multicolor ? 0.065 : 0.045),
      in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(
          contrast == .increased ? accent.opacity(0.62) : Color.secondary.opacity(0.16),
          lineWidth: contrast == .increased ? 1.5 : 1))
    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .onTapGesture { onOpen?() }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Power flow")
    .accessibilityValue(systemPower)
    .help(onOpen == nil ? "" : L10n.string("Open power details"))
  }

  private func powerTile(
    title: String,
    value: String,
    detail: String,
    symbol: String,
    metric: MetricKind
  ) -> some View {
    let color = theme.color(for: metric)
    return VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: symbol)
        .font(.caption)
        .foregroundStyle(color)
        .lineLimit(1)
      Text(value)
        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.78)
      Text(detail)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
    .background(
      reduceTransparency ? Color(nsColor: .windowBackgroundColor) : color.opacity(0.055),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private var systemPowerWatts: Double? {
    guard let value = snapshot.power.value?.estimatedSystemPowerWatts,
      value.isFinite,
      value >= 0
    else { return nil }
    return value
  }

  private var rawBatteryPowerWatts: Double? {
    let value = snapshot.power.value?.batteryPowerWatts
      ?? snapshot.battery.value?.batteryPowerWatts
    guard let value, value.isFinite else { return nil }
    return value
  }

  private var adapterInputPowerWatts: Double? {
    guard let value = snapshot.power.value?.adapterInputPowerWatts,
      value.isFinite,
      value >= 0
    else { return nil }
    return value
  }

  private var systemPower: String {
    MetricNumberFormatter.decimalWatts(
      systemPowerWatts,
      estimated: snapshot.power.isEstimated)
      ?? L10n.string("Collecting data")
  }

  private var batteryPower: String {
    MetricNumberFormatter.decimalWatts(rawBatteryPowerWatts, absolute: true)
      ?? L10n.string("Collecting data")
  }

  private var adapterInputPower: String {
    MetricNumberFormatter.decimalWatts(adapterInputPowerWatts)
      ?? L10n.string("Not measured")
  }

  private var batteryFlowState: BatteryPowerFlowState {
    BatteryPowerFlowState.resolve(rawBatteryPowerWatts)
  }

  private var systemPowerDetail: String {
    if systemPowerWatts == nil { return L10n.string("Waiting for a valid sensor reading") }
    return snapshot.power.isEstimated
      ? L10n.string("Calculated from battery telemetry")
      : L10n.string("Direct sensor")
  }

  private var adapterDetail: String {
    if adapterInputPowerWatts != nil { return L10n.string("Measured adapter input") }
    if let rated = MetricNumberFormatter.ratedWatts(snapshot.adapter.value?.ratedPowerWatts) {
      return rated
    }
    return L10n.string("Adapter rating unavailable")
  }

  private var sourceBadge: some View {
    Label(
      snapshot.power.isEstimated ? L10n.string("Calculated") : L10n.string("Direct telemetry"),
      systemImage: snapshot.power.isEstimated ? "function" : "sensor.tag.radiowaves.forward.fill"
    )
    .font(.caption2.bold())
    .foregroundStyle(.secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(.quaternary.opacity(0.45), in: Capsule())
  }

  private var statusBadge: some View {
    let status = snapshot.power.value?.status ?? .unknown
    return Label(status.displayName, systemImage: status.symbolName)
      .font(.caption.bold())
      .foregroundStyle(statusColor(status))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.quaternary.opacity(0.45), in: Capsule())
  }

  private func statusColor(_ status: PowerSufficiencyStatus) -> Color {
    switch status {
    case .insufficient, .sensorConflict: return .red
    case .borderline: return .orange
    case .unknown: return .secondary
    default: return theme.color(for: .systemPower)
    }
  }

  private var powerSourceTitle: String {
    guard let battery = snapshot.battery.value else { return L10n.string("Power source unknown") }
    return battery.externalPowerConnected ? L10n.string("Connected to adapter") : L10n.string("On battery")
  }

  private var powerSourceSymbol: String {
    snapshot.battery.value?.externalPowerConnected == true ? "powerplug.fill" : "battery.75percent"
  }
}
