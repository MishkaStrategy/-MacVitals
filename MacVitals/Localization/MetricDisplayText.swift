import Foundation

extension MetricAvailability {
  var displayName: String {
    switch self {
    case .available: return L10n.string("Available")
    case .temporarilyUnavailable: return L10n.string("Temporarily unavailable")
    case .unsupported: return L10n.string("Unsupported")
    case .permissionRequired: return L10n.string("Permission required")
    case .providerError: return L10n.string("Provider error")
    case .stale: return L10n.string("Stale")
    case .estimated: return L10n.string("Estimated")
    }
  }
}

extension MetricSource {
  var displayName: String {
    switch self {
    case .machHostStatistics: return L10n.string("Mach host statistics")
    case .iokitPowerSources: return L10n.string("IOKit power sources")
    case .iokitRegistry: return L10n.string("IOKit registry")
    case .metal: return L10n.string("Metal")
    case .derivedPowerModel: return L10n.string("Derived power model")
    case .unavailable: return L10n.string("Unavailable")
    }
  }
}

extension PowerSufficiencyStatus {
  var displayName: String {
    switch self {
    case .sufficient: return L10n.string("Sufficient")
    case .insufficient: return L10n.string("Insufficient")
    case .borderline: return L10n.string("Borderline")
    case .chargingBattery: return L10n.string("Charging")
    case .notConnected: return L10n.string("On battery")
    case .sensorConflict: return L10n.string("Sensor conflict")
    case .powerAdapterOnly: return L10n.string("Adapter power")
    case .unknown: return L10n.string("Unknown")
    }
  }

  var symbolName: String {
    switch self {
    case .sufficient: return "checkmark.circle"
    case .insufficient: return "exclamationmark.triangle.fill"
    case .borderline: return "gauge.with.dots.needle.50percent"
    case .chargingBattery: return "bolt.circle"
    case .notConnected: return "battery.75percent"
    case .sensorConflict: return "exclamationmark.triangle"
    case .powerAdapterOnly: return "powerplug"
    case .unknown: return "questionmark.circle"
    }
  }
}

nonisolated enum BatteryDisplayText {
  static func summary(_ metric: MetricValue<BatteryStats>) -> String {
    guard let battery = metric.value else { return metric.availability.displayName }
    guard battery.present else { return L10n.string("No battery") }
    return MetricNumberFormatter.percentage(battery.percentage)
  }
}

nonisolated enum BatteryPowerFlowState: Equatable, Sendable {
  case supportingSystem
  case charging
  case idle
  case unavailable

  static func resolve(_ batteryPowerWatts: Double?) -> Self {
    guard let batteryPowerWatts, batteryPowerWatts.isFinite else { return .unavailable }
    if batteryPowerWatts < 0 { return .supportingSystem }
    if batteryPowerWatts > 0 { return .charging }
    return .idle
  }

  var displayName: String {
    switch self {
    case .supportingSystem: return L10n.string("Supporting system")
    case .charging: return L10n.string("Charging")
    case .idle: return L10n.string("No net battery flow")
    case .unavailable: return L10n.string("Unknown")
    }
  }

  var symbolName: String {
    switch self {
    case .supportingSystem: return "arrow.right"
    case .charging: return "arrow.left"
    case .idle: return "minus"
    case .unavailable: return "arrow.left.and.right"
    }
  }
}

nonisolated enum GPUMemoryDisplayText {
  static func summary(hasUnifiedMemory: Bool?) -> String {
    guard let hasUnifiedMemory else { return L10n.string("memory type unavailable") }
    return L10n.string(hasUnifiedMemory ? "unified memory" : "discrete memory")
  }
}

nonisolated enum MetricNumberFormatter {
  static func percentage(_ value: Double?) -> String {
    boundedRoundedInteger(value, range: 0...100).map { "\($0)%" } ?? "—"
  }

  static func ratedWatts(_ value: Double?) -> String? {
    boundedRoundedInteger(value, range: 0...10_000).map {
      L10n.format("Rated %d W", $0)
    }
  }

  static func decimalWatts(
    _ value: Double?,
    estimated: Bool = false,
    absolute: Bool = false
  ) -> String? {
    guard let value, value.isFinite else { return nil }
    let displayed = absolute ? abs(value) : value
    guard displayed.isFinite, (0...100_000).contains(displayed) else { return nil }
    return estimated
      ? L10n.format("~%.1f W", displayed)
      : L10n.format("%.1f W", displayed)
  }

  static func isNegative(_ value: Double?) -> Bool? {
    guard let value, value.isFinite else { return nil }
    return value < 0
  }

  private static func boundedRoundedInteger(
    _ value: Double?,
    range: ClosedRange<Double>
  ) -> Int? {
    guard let value, value.isFinite, range.contains(value) else { return nil }
    return Int(value.rounded())
  }
}
