import AppKit
import Foundation

nonisolated struct MenuBarStatusSegment: Equatable {
  let metric: MenuMetric
  let state: MenuBarIconState
  let value: String
}

nonisolated enum MenuBarStatusTitleRenderer {
  static func segments(
    snapshot: SystemSnapshot,
    metrics: [MenuMetric]
  ) -> [MenuBarStatusSegment] {
    MenuLayoutRules.normalized(metrics).map { metric in
      MenuBarStatusSegment(
        metric: metric,
        state: MenuBarIconCatalog.state(for: metric, snapshot: snapshot),
        value: compactValue(for: metric, snapshot: snapshot))
    }
  }

  static func compactText(
    snapshot: SystemSnapshot,
    metrics: [MenuMetric]
  ) -> String {
    segments(snapshot: snapshot, metrics: metrics)
      .map(\.value)
      .joined(separator: "   ")
  }

  @MainActor
  static func statusBarForegroundColor(for appearance: NSAppearance) -> NSColor {
    let darkMatches: [NSAppearance.Name] = [.vibrantDark, .darkAqua]
    let lightMatches: [NSAppearance.Name] = [.vibrantLight, .aqua]
    let match = appearance.bestMatch(from: darkMatches + lightMatches)

    if match == .vibrantDark || match == .darkAqua {
      return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.94)
    }

    return NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 0.92)
  }

  @MainActor
  static func attributedTitle(
    snapshot: SystemSnapshot,
    metrics: [MenuMetric],
    appearance: NSAppearance
  ) -> NSAttributedString {
    let segments = segments(snapshot: snapshot, metrics: metrics)
    let foregroundColor = statusBarForegroundColor(for: appearance)
    let result = NSMutableAttributedString(string: "")

    guard !segments.isEmpty else {
      appendIcon(
        metric: .cpu,
        state: .normal,
        foregroundColor: foregroundColor,
        to: result)
      return result
    }

    for (index, segment) in segments.enumerated() {
      if index > 0 {
        result.append(
          NSAttributedString(
            string: "   ",
            attributes: separatorAttributes(foregroundColor: foregroundColor)))
      }

      appendIcon(
        metric: segment.metric,
        state: segment.state,
        foregroundColor: foregroundColor,
        to: result)
      result.append(NSAttributedString(string: "\u{202F}"))
      result.append(
        NSAttributedString(
          string: segment.value,
          attributes: valueAttributes(
            for: segment.state,
            foregroundColor: foregroundColor)))
    }

    return result
  }

  private static func compactValue(
    for metric: MenuMetric,
    snapshot: SystemSnapshot
  ) -> String {
    switch metric {
    case .cpu:
      return percentage(snapshot.cpu.value?.total).map { "\($0)%" } ?? "—"
    case .gpu:
      return percentage(snapshot.gpu.value?.systemUtilizationPercent).map { "\($0)%" } ?? "—"
    case .memory:
      return percentage(snapshot.memory.value?.usedPercent).map { "\($0)%" } ?? "—"
    case .temperature:
      return temperatureSummary(snapshot.temperature.value)
    case .battery:
      return percentage(snapshot.battery.value?.percentage).map { "\($0)%" } ?? "—"
    case .fans:
      return fanSummary(snapshot.fans.value?.fans)
    case .systemPower:
      return decimalWatts(snapshot.power.value?.estimatedSystemPowerWatts) ?? "—"
    case .adapterPower:
      return decimalWatts(snapshot.power.value?.adapterInputPowerWatts)
        ?? snapshot.adapter.value?.ratedPowerWatts.flatMap { boundedInteger($0, range: 0...10_000) }
          .map { "≤\($0)W" }
        ?? "—"
    case .powerStatus:
      return powerStatus(snapshot.power.value?.status)
    }
  }

  private static func temperatureSummary(_ stats: TemperatureStats?) -> String {
    guard let stats else { return "—" }
    let processor = temperature(stats.processorCelsius)
    let battery = temperature(stats.batteryCelsius)

    switch (processor, battery) {
    case (.some(let cpu), .some(let battery)):
      return "\(cpu)°/\(battery)°"
    case (.some(let cpu), .none):
      return "\(cpu)°"
    case (.none, .some(let battery)):
      return "\(battery)°"
    case (.none, .none):
      return "—"
    }
  }

  private static func fanSummary(_ fans: [FanReading]?) -> String {
    guard let fans, !fans.isEmpty else { return "—" }

    let values = fans.prefix(2).compactMap { fan -> Int? in
      guard let rpm = fan.currentRPM else { return nil }
      return boundedInteger(rpm, range: 0...100_000)
    }

    return values.isEmpty ? "—" : values.map(String.init).joined(separator: "/")
  }

  private static func percentage(_ value: Double?) -> Int? {
    boundedInteger(value, range: 0...100)
  }

  private static func temperature(_ value: Double?) -> Int? {
    boundedInteger(value, range: -20...130)
  }

  private static func decimalWatts(_ value: Double?) -> String? {
    guard let value, value.isFinite, (0...10_000).contains(abs(value)) else { return nil }
    return String(format: "%.1fW", abs(value))
  }

  private static func boundedInteger(
    _ value: Double?,
    range: ClosedRange<Double>
  ) -> Int? {
    guard let value, value.isFinite, range.contains(value) else { return nil }
    return Int(value.rounded())
  }

  private static func powerStatus(_ status: PowerSufficiencyStatus?) -> String {
    switch status {
    case .insufficient: return "!"
    case .borderline: return "◐"
    case .chargingBattery: return "↯"
    case .sufficient: return "✓"
    case .notConnected: return "—"
    case .sensorConflict: return "!?"
    case .powerAdapterOnly: return "⌁"
    case .unknown, nil: return "?"
    }
  }

  @MainActor
  private static func appendIcon(
    metric: MenuMetric,
    state: MenuBarIconState,
    foregroundColor: NSColor,
    to result: NSMutableAttributedString
  ) {
    guard let image = MenuBarIconCatalog.minimalImage(for: metric, state: state) else {
      result.append(
        NSAttributedString(
          string: "·",
          attributes: valueAttributes(
            for: state,
            foregroundColor: foregroundColor)))
      return
    }

    let colorConfiguration = NSImage.SymbolConfiguration(
      hierarchicalColor: foregroundColor)
    let tintedImage = image.withSymbolConfiguration(colorConfiguration) ?? image
    tintedImage.size = image.size
    tintedImage.isTemplate = false

    let attachment = NSTextAttachment()
    attachment.image = tintedImage
    attachment.bounds = NSRect(
      x: 0,
      y: -1.5,
      width: tintedImage.size.width,
      height: tintedImage.size.height)
    result.append(NSAttributedString(attachment: attachment))
  }

  @MainActor
  private static func valueAttributes(
    for state: MenuBarIconState,
    foregroundColor: NSColor
  ) -> [NSAttributedString.Key: Any] {
    let weight: NSFont.Weight
    switch state {
    case .normal: weight = .regular
    case .elevated: weight = .medium
    case .critical: weight = .semibold
    }

    return [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: weight),
      .foregroundColor: foregroundColor,
      .kern: -0.15,
    ]
  }

  @MainActor
  private static func separatorAttributes(
    foregroundColor: NSColor
  ) -> [NSAttributedString.Key: Any] {
    [
      .font: NSFont.systemFont(ofSize: 11, weight: .regular),
      .foregroundColor: foregroundColor,
    ]
  }
}
