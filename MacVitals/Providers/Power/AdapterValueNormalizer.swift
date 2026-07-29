import Foundation

nonisolated enum AdapterValueNormalizer {
  static func finiteNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber else { return nil }
    let result = number.doubleValue
    return result.isFinite ? result : nil
  }

  static func ratedPowerWatts(_ value: Double?) -> Double? {
    guard let value, value.isFinite, (1...1_000).contains(value) else { return nil }
    return value
  }

  static func milliampsToAmps(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    let amperes = value / 1_000
    guard (0...20).contains(amperes) else { return nil }
    return amperes
  }
}
