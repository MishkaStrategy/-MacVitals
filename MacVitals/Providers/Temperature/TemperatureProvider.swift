import Foundation

nonisolated enum TemperatureValueNormalizer {
  static let plausibleProcessorRange = 5.0...130.0
  static let plausibleBatteryRange = 0.0...100.0
  static let plausibleSensorRange = -10.0...130.0

  static func processor(_ value: Double?) -> Double? {
    guard let value, value.isFinite, plausibleProcessorRange.contains(value) else { return nil }
    return value
  }

  static func battery(_ value: Double?) -> Double? {
    guard let value, value.isFinite, plausibleBatteryRange.contains(value) else { return nil }
    return value
  }

  static func sensor(_ value: Double?) -> Double? {
    guard let value, value.isFinite, plausibleSensorRange.contains(value) else { return nil }
    return value
  }
}

final class TemperatureProvider: @unchecked Sendable {
  private static let preferredProcessorKeys = [
    "TCMz", // CPU die hotspot on supported Apple Silicon models.
    "Tp09", "Tp01", "Tp05", "Tp0D", "Tp0P", "Tp0E", "Tp0F", "Tp0H", "Tp0b",
  ]

  private static let fallbackTemperatureKeys = [
    "TCMz", "Tp09", "Tp01", "Tp05", "Tp0D", "Tp0P", "Tp0E", "Tp0F", "Tp0H", "Tp0b",
    "Tg0f", "Tg0j", "Tg0a", "Tg0b", "Tg0c", "Tg0d", "Tg0e", "Tg0k",
    "Tm0P", "Tm1P", "Tm0p", "Tm1p", "TH0x", "TH1x", "Ts0P", "Ts1P",
    "TB0T", "TB1T", "Ta0P", "Ta1P", "TP0P", "Ts0S", "Ts1S", "Ts2S",
  ]

  private static let supportedTemperatureTypes: Set<String> = ["sp78", "flt ", "fpe2"]
  private static let maximumDiscoveredSensors = 48

  private var connection: AppleSMCConnection?
  private var discoveredKeys: [String]?
  private var cachedSMCReadings: [TemperatureReading] = []
  private var lastSMCSampleAt: Date?

  func resetConnection() {
    connection = nil
    discoveredKeys = nil
    cachedSMCReadings = []
    lastSMCSampleAt = nil
  }

  func sample(
    batteryTemperatureCelsius: Double?,
    now: Date = Date()
  ) -> MetricValue<TemperatureStats> {
    let battery = TemperatureValueNormalizer.battery(batteryTemperatureCelsius)
    let smcReadings = currentSMCReadings(now: now)
    let processorReading = primaryProcessorReading(in: smcReadings)

    var readings = smcReadings
    if let battery {
      let batteryReading = TemperatureReading(
        id: "battery.iokit",
        name: TemperatureL10n.string("Battery temperature"),
        category: .battery,
        celsius: battery,
        source: .iokitRegistry,
        isPrimary: true)
      let insertionIndex = readings.firstIndex {
        Self.readingSort(batteryReading, $0)
      } ?? readings.endIndex
      readings.insert(batteryReading, at: insertionIndex)
    }

    let maximum = readings.max { $0.celsius < $1.celsius }?.celsius
    guard processorReading != nil || battery != nil || !readings.isEmpty else {
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
        processorCelsius: processorReading?.celsius,
        batteryCelsius: battery,
        maximumCelsius: maximum,
        processorSensorKey: processorReading?.key,
        sensors: readings),
      unit: .celsius,
      availability: .available,
      quality: smcReadings.isEmpty ? .direct : .experimental,
      source: smcReadings.isEmpty ? .iokitRegistry : .appleSMC,
      timestamp: now,
      isEstimated: false,
      message: smcReadings.isEmpty
        ? TemperatureL10n.string("Battery temperature")
        : TemperatureL10n.string("Detailed temperatures from Apple SMC and IOKit"))
  }

  private func currentSMCReadings(now: Date) -> [TemperatureReading] {
    if let lastSMCSampleAt,
      now.timeIntervalSince(lastSMCSampleAt) < SamplingIntervalPolicy.temperatureMinimumInterval
    {
      return cachedSMCReadings
    }

    guard let source = smcConnection() else { return cachedSMCReadings }
    let keys = temperatureKeys(source: source)
    let readings = keys.compactMap { reading(key: $0, source: source) }
      .sorted(by: Self.readingSort)
    cachedSMCReadings = readings
    lastSMCSampleAt = now
    return readings
  }

  private func temperatureKeys(source: AppleSMCConnection) -> [String] {
    if let discoveredKeys { return discoveredKeys }

    let enumerated = (try? source.keyNames()) ?? []
    let temperatureKeys = enumerated.filter { key in
      key.count == 4 && key.first == "T"
    }
    let preferred = Self.fallbackTemperatureKeys + temperatureKeys.sorted()
    var seen = Set<String>()
    let normalized = preferred.filter { seen.insert($0).inserted }
    let limited = Array(normalized.prefix(Self.maximumDiscoveredSensors))
    discoveredKeys = limited
    return limited
  }

  private func reading(key: String, source: AppleSMCConnection) -> TemperatureReading? {
    guard let raw = try? source.readKey(key),
      Self.supportedTemperatureTypes.contains(raw.dataType),
      let value = TemperatureValueNormalizer.sensor(AppleSMCDataDecoder.number(raw))
    else { return nil }

    let category = Self.category(for: key)
    return TemperatureReading(
      id: "smc.\(key)",
      key: key,
      name: Self.name(for: key, category: category),
      category: category,
      celsius: value,
      source: .appleSMC,
      isPrimary: key == "TCMz")
  }

  private func primaryProcessorReading(in readings: [TemperatureReading]) -> TemperatureReading? {
    if let hotspot = readings.first(where: { $0.key == "TCMz" }) { return hotspot }
    for key in Self.preferredProcessorKeys {
      if let reading = readings.first(where: { $0.key == key }) { return reading }
    }
    return readings.filter { $0.category == .processor }.max { $0.celsius < $1.celsius }
  }

  private func smcConnection() -> AppleSMCConnection? {
    if let connection { return connection }
    guard let created = try? AppleSMCConnection() else { return nil }
    connection = created
    return created
  }

  private static func category(for key: String) -> TemperatureSensorCategory {
    if key.hasPrefix("TC") || key.hasPrefix("Tp") { return .processor }
    if key.hasPrefix("Tg") || key.hasPrefix("TG") { return .graphics }
    if key.hasPrefix("Tm") { return .memory }
    if key.hasPrefix("TH") || key.hasPrefix("Ts") { return .storage }
    if key.hasPrefix("TB") { return .battery }
    if key.hasPrefix("Ta") || key.hasPrefix("TP") { return .power }
    if key.hasPrefix("TW") || key.hasPrefix("TL") || key.hasPrefix("TR") { return .enclosure }
    return .other
  }

  private static func name(for key: String, category: TemperatureSensorCategory) -> String {
    switch key {
    case "TCMz": return TemperatureL10n.string("CPU hotspot")
    case "Tg0f", "Tg0j": return TemperatureL10n.string("GPU sensor")
    case "Tm0P", "Tm1P", "Tm0p", "Tm1p": return TemperatureL10n.string("Memory sensor")
    case "TH0x", "TH1x", "Ts0P", "Ts1P": return TemperatureL10n.string("Storage sensor")
    case "TB0T", "TB1T": return TemperatureL10n.string("Battery SMC sensor")
    default: return category.displayName
    }
  }

  private static func readingSort(_ lhs: TemperatureReading, _ rhs: TemperatureReading) -> Bool {
    let lhsRank = categoryRank(lhs.category)
    let rhsRank = categoryRank(rhs.category)
    if lhsRank != rhsRank { return lhsRank < rhsRank }
    if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
    if lhs.name != rhs.name { return lhs.name < rhs.name }
    return (lhs.key ?? lhs.id) < (rhs.key ?? rhs.id)
  }

  private static func categoryRank(_ category: TemperatureSensorCategory) -> Int {
    switch category {
    case .processor: return 0
    case .graphics: return 1
    case .memory: return 2
    case .storage: return 3
    case .battery: return 4
    case .power: return 5
    case .enclosure: return 6
    case .other: return 7
    }
  }
}
