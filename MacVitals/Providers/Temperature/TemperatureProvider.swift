import Foundation

nonisolated enum TemperatureValueNormalizer {
  static let plausibleProcessorRange = 5.0...130.0
  static let plausibleBatteryRange = 0.0...100.0

  static func processor(_ value: Double?) -> Double? {
    guard let value, value.isFinite, plausibleProcessorRange.contains(value) else { return nil }
    return value
  }

  static func battery(_ value: Double?) -> Double? {
    guard let value, value.isFinite, plausibleBatteryRange.contains(value) else { return nil }
    return value
  }
}

final class TemperatureProvider: @unchecked Sendable {
  private static let processorKeys = [
    "TCMz", // CPU die hotspot on supported Apple Silicon models.
    "Tp09", "Tp01", "Tp05", "Tp0D", "Tp0P", "Tp0E", "Tp0F", "Tp0H", "Tp0b",
  ]

  private var connection: AppleSMCConnection?

  func resetConnection() {
    connection = nil
  }

  func sample(batteryTemperatureCelsius: Double?) -> MetricValue<TemperatureStats> {
    let now = Date()
    let processorReading = readProcessorTemperature()
    let battery = TemperatureValueNormalizer.battery(batteryTemperatureCelsius)
    let maximum = [processorReading?.value, battery].compactMap { $0 }.max()

    guard processorReading != nil || battery != nil else {
      return MetricValue(
        value: nil,
        unit: .celsius,
        availability: .temporarilyUnavailable,
        quality: .unknown,
        source: .unavailable,
        timestamp: now,
        isEstimated: false,
        message: TemperatureL10n.string("Temperature sensors are unavailable"))
    }

    return MetricValue(
      value: TemperatureStats(
        processorCelsius: processorReading?.value,
        batteryCelsius: battery,
        maximumCelsius: maximum,
        processorSensorKey: processorReading?.key),
      unit: .celsius,
      availability: .available,
      quality: processorReading == nil ? .direct : .experimental,
      source: processorReading == nil ? .iokitRegistry : .appleSMC,
      timestamp: now,
      isEstimated: false,
      message: processorReading == nil
        ? TemperatureL10n.string("Battery temperature")
        : TemperatureL10n.string("Processor temperature from Apple SMC"))
  }

  private func readProcessorTemperature() -> (key: String, value: Double)? {
    guard let source = smcConnection() else { return nil }

    var readings: [(key: String, value: Double)] = []
    for key in Self.processorKeys {
      guard let raw = try? source.readKey(key),
        let value = TemperatureValueNormalizer.processor(AppleSMCDataDecoder.number(raw))
      else { continue }
      readings.append((key, value))
    }

    if let hotspot = readings.first(where: { $0.key == "TCMz" }) {
      return hotspot
    }
    return readings.max { $0.value < $1.value }
  }

  private func smcConnection() -> AppleSMCConnection? {
    if let connection { return connection }
    guard let created = try? AppleSMCConnection() else { return nil }
    connection = created
    return created
  }
}
