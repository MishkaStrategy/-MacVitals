import Foundation

nonisolated enum MenuBarRenderer {
  static func render(
    snapshot: SystemSnapshot,
    metrics: [MenuMetric],
    maximumCharacters: Int = 96
  ) -> String {
    guard maximumCharacters > 0 else { return "" }
    let parts = MenuLayoutRules.normalized(metrics).map { render(metric: $0, snapshot: snapshot) }
    let joined = parts.isEmpty ? "◉" : parts.joined(separator: "  ·  ")
    guard joined.count > maximumCharacters else { return joined }
    guard maximumCharacters > 1 else { return "…" }
    return String(joined.prefix(maximumCharacters - 1)) + "…"
  }

  private static func render(metric: MenuMetric, snapshot: SystemSnapshot) -> String {
    switch metric {
    case .cpu:
      return percentage(snapshot.cpu.value?.total).map { "CPU \($0)%" } ?? "CPU —"
    case .gpu:
      return percentage(snapshot.gpu.value?.systemUtilizationPercent).map { "GPU \($0)%" }
        ?? "GPU —"
    case .memory:
      return percentage(snapshot.memory.value?.usedPercent).map { "RAM \($0)%" } ?? "RAM —"
    case .temperature:
      return temperatureSummary(snapshot.temperature.value)
    case .battery:
      let percentageText = percentage(snapshot.battery.value?.percentage).map { "\($0)%" }
      let values = [percentageText].compactMap { $0 }
      return values.isEmpty ? "🔋 —" : "🔋 " + values.joined(separator: " ")
    case .fans:
      return FanDisplayText.menuBar(snapshot.fans)
    case .systemPower:
      return decimalWatts(snapshot.power.value?.estimatedSystemPowerWatts)
        .map { "⚡ \($0)" } ?? "⚡ —"
    case .adapterPower:
      return decimalWatts(snapshot.power.value?.adapterInputPowerWatts)
        .map { "🔌 \($0)" }
        ?? watts(snapshot.adapter.value?.ratedPowerWatts).map { "🔌 ≤\($0) W" }
        ?? "🔌 —"
    case .powerStatus:
      return powerIcon(snapshot.power.value?.status)
    }
  }

  private static func temperatureSummary(_ stats: TemperatureStats?) -> String {
    guard let stats else { return "🌡 —" }
    let processor = temperature(stats.processorCelsius)
    let battery = temperature(stats.batteryCelsius)
    switch (processor, battery) {
    case (.some(let cpu), .some(let battery)):
      return "🌡 \(cpu)°/\(battery)°"
    case (.some(let cpu), .none):
      return "🌡 \(cpu)°"
    case (.none, .some(let battery)):
      return "🌡 🔋\(battery)°"
    case (.none, .none):
      return "🌡 —"
    }
  }

  private static func percentage(_ value: Double?) -> Int? {
    boundedInteger(value, range: 0...100)
  }

  private static func temperature(_ value: Double?) -> Int? {
    boundedInteger(value, range: -20...130)
  }

  private static func watts(_ value: Double?) -> Int? {
    boundedInteger(value, range: 0...10_000)
  }

  private static func decimalWatts(_ value: Double?) -> String? {
    guard let value, value.isFinite, (0...10_000).contains(abs(value)) else { return nil }
    return String(format: "%.1f W", abs(value))
  }

  private static func boundedInteger(
    _ value: Double?,
    range: ClosedRange<Double>
  ) -> Int? {
    guard let value, value.isFinite, range.contains(value) else { return nil }
    return Int(value.rounded())
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
