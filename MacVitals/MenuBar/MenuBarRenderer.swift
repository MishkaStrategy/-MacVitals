import Foundation

nonisolated enum MenuBarRenderer {
  static func render(
    snapshot: SystemSnapshot,
    metrics: [MenuMetric],
    maximumCharacters: Int = 80
  ) -> String {
    let parts = MenuLayoutRules.normalized(metrics).map { render(metric: $0, snapshot: snapshot) }
    let joined = parts.isEmpty ? "◉" : parts.joined(separator: " · ")
    guard maximumCharacters > 1, joined.count > maximumCharacters else { return joined }
    return String(joined.prefix(maximumCharacters - 1)) + "…"
  }

  private static func render(metric: MenuMetric, snapshot: SystemSnapshot) -> String {
    switch metric {
    case .cpu:
      return snapshot.cpu.value.map { "CPU \(Int($0.total.rounded()))%" } ?? "CPU —"
    case .gpu:
      if let utilization = snapshot.gpu.value?.systemUtilizationPercent {
        return "GPU \(Int(utilization.rounded()))%"
      }
      return snapshot.gpu.value?.metalAvailable == true ? "GPU Metal" : "GPU —"
    case .memory:
      return snapshot.memory.value.map { "RAM \(Int($0.usedPercent.rounded()))%" } ?? "RAM —"
    case .battery:
      return snapshot.battery.value?.percentage.map { "🔋 \(Int($0.rounded()))%" } ?? "🔋 —"
    case .adapterPower:
      return snapshot.adapter.value?.ratedPowerWatts.map { "⚡ \(Int($0.rounded())) W" } ?? "⚡ —"
    case .powerStatus:
      return powerIcon(snapshot.power.value?.status)
    }
  }

  private static func powerIcon(_ status: PowerSufficiencyStatus?) -> String {
    switch status {
    case .insufficient: return "⚠︎"
    case .borderline: return "◐"
    case .chargingBattery: return "↯"
    case .sufficient: return "✓"
    case .notConnected: return "🔋"
    case .sensorConflict: return "!?"
    case .powerAdapterOnly: return "⌁"
    case .unknown, nil: return "?"
    }
  }
}
