import Foundation

nonisolated enum AdapterValueNormalizer {
  static func firstFiniteNumber(keys: [String], in details: [String: Any]) -> Double? {
    for key in keys {
      guard let number = details[key] as? NSNumber else { continue }
      let value = number.doubleValue
      if value.isFinite { return value }
    }
    return nil
  }

  static func ratedPowerWatts(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (1...1_000).contains(value) else { return nil }
    return value
  }

  static func voltageVolts(_ raw: Double?) -> Double? {
    guard let raw, raw.isFinite else { return nil }
    let volts = raw > 100 ? raw / 1_000 : raw
    guard (0...100).contains(volts) else { return nil }
    return volts
  }

  static func currentAmperes(_ raw: Double?) -> Double? {
    guard let raw, raw.isFinite else { return nil }
    let amperes = raw > 100 ? raw / 1_000 : raw
    guard (0...20).contains(amperes) else { return nil }
    return amperes
  }

  static func text(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(256))
  }
}
