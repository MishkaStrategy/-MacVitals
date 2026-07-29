import Foundation

nonisolated enum BatteryValueNormalizer {
  static func finiteNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber else { return nil }
    let result = number.doubleValue
    return result.isFinite ? result : nil
  }

  static func percentage(current: Double?, maximum: Double?) -> Double? {
    guard let current, let maximum,
      current.isFinite, maximum.isFinite,
      current >= 0, maximum > 0
    else { return nil }
    return min(100, max(0, current / maximum * 100))
  }

  static func capacityMah(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (0...100_000).contains(value) else { return nil }
    return value
  }

  static func healthPercent(maximumMah: Double?, designMah: Double?) -> Double? {
    percentage(current: maximumMah, maximum: designMah)
  }

  static func cycleCount(_ value: Any?) -> Int? {
    guard let raw = finiteNumber(value),
      raw.rounded(.towardZero) == raw,
      (0...100_000).contains(raw)
    else { return nil }
    return Int(raw)
  }

  static func temperatureCelsius(raw: Double?) -> Double? {
    guard let raw, raw.isFinite else { return nil }
    let celsius = raw > 100 ? raw / 100 : raw
    guard (-20...100).contains(celsius) else { return nil }
    return celsius
  }

  static func millivoltsToVolts(_ value: Double?) -> Double? {
    guard let value, value.isFinite, value > 0 else { return nil }
    let volts = value / 1_000
    guard volts > 0, volts <= 30 else { return nil }
    return volts
  }

  static func milliampsToAmps(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    let amperes = value / 1_000
    guard (-30...30).contains(amperes) else { return nil }
    return amperes
  }

  static func powerWatts(voltage: Double?, current: Double?) -> Double? {
    guard let voltage, let current,
      voltage.isFinite, voltage > 0,
      current.isFinite
    else { return nil }
    let watts = voltage * current
    return watts.isFinite ? watts : nil
  }

  static func validMinutes(_ value: Int?) -> Int? {
    guard let value, (0..<100_000).contains(value) else { return nil }
    return value
  }

  static func text(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(256))
  }

  static func state(
    charging: Bool,
    externalPower: Bool,
    percentage: Double?
  ) -> BatteryState {
    if charging { return .charging }
    if externalPower, (percentage ?? 0) >= 99 { return .charged }
    if externalPower { return .adapterPower }
    return .discharging
  }
}
