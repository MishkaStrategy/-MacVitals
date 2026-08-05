import Foundation

nonisolated struct SystemPowerTelemetryReading: Sendable, Equatable {
  let systemLoadWatts: Double
  let systemInputWatts: Double?
}

nonisolated enum SystemPowerTelemetryNormalizer {
  static func watts(fromMilliwatts value: Any?) -> Double? {
    guard let number = value as? NSNumber else { return nil }
    let milliwatts = number.doubleValue
    guard milliwatts.isFinite, (0...500_000).contains(milliwatts) else { return nil }
    return milliwatts / 1_000
  }
}

struct SystemPowerTelemetryProvider: Sendable {
  func sample() -> SystemPowerTelemetryReading? {
    let dictionary = SmartBatteryRegistryCache.shared.snapshot()
    guard
      let telemetry = dictionary["PowerTelemetryData"] as? [String: Any],
      let systemLoad = SystemPowerTelemetryNormalizer.watts(
        fromMilliwatts: telemetry["SystemLoad"]),
      systemLoad > 0.01
    else { return nil }

    return SystemPowerTelemetryReading(
      systemLoadWatts: systemLoad,
      systemInputWatts: SystemPowerTelemetryNormalizer.watts(
        fromMilliwatts: telemetry["SystemPowerIn"]))
  }
}
