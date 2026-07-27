import Foundation

nonisolated enum MetricAvailability: String, Codable, Sendable {
  case available
  case temporarilyUnavailable
  case unsupported
  case permissionRequired
  case providerError
  case stale
  case estimated
}

nonisolated enum MeasurementQuality: String, Codable, Sendable {
  case direct
  case derived
  case estimated
  case experimental
  case unknown
}

nonisolated enum MetricSource: String, Codable, Sendable {
  case machHostStatistics
  case iokitPowerSources
  case iokitRegistry
  case appleSMC
  case metal
  case derivedPowerModel
  case unavailable
}

nonisolated enum MetricUnit: String, Codable, Sendable {
  case percent = "%"
  case bytes = "B"
  case watts = "W"
  case volts = "V"
  case amperes = "A"
  case celsius = "°C"
  case rpm = "RPM"
  case seconds = "s"
  case count = "count"
  case text = ""
}

nonisolated struct MetricValue<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable
{
  let value: Value?
  let unit: MetricUnit
  let availability: MetricAvailability
  let quality: MeasurementQuality
  let source: MetricSource
  let timestamp: Date
  let isEstimated: Bool
  let message: String?

  static func unavailable(
    unit: MetricUnit,
    availability: MetricAvailability = .unsupported,
    source: MetricSource = .unavailable,
    message: String? = nil
  ) -> Self {
    .init(
      value: nil, unit: unit, availability: availability, quality: .unknown,
      source: source, timestamp: Date(), isEstimated: false, message: message)
  }
}

nonisolated struct CPUStats: Codable, Sendable, Equatable {
  let total: Double
  let user: Double
  let system: Double
  let idle: Double
  let logicalProcessors: Int
  let activeProcessors: Int
}

nonisolated enum MemoryPressureLevel: String, Codable, Sendable {
  case normal
  case warning
  case critical
  case unknown
}

nonisolated struct MemoryStats: Codable, Sendable, Equatable {
  let physicalBytes: UInt64
  let usedBytes: UInt64
  let freeBytes: UInt64
  let availableBytes: UInt64
  let activeBytes: UInt64
  let inactiveBytes: UInt64
  let wiredBytes: UInt64
  let compressedBytes: UInt64
  let purgeableBytes: UInt64
  let speculativeBytes: UInt64
  let swapTotalBytes: UInt64?
  let swapUsedBytes: UInt64?
  let swapFreeBytes: UInt64?
  let pressureLevel: MemoryPressureLevel
  let usedPercent: Double
}

nonisolated enum BatteryState: String, Codable, Sendable {
  case charging
  case discharging
  case charged
  case paused
  case adapterPower
  case unknown
  case absent
}

nonisolated struct BatteryStats: Codable, Sendable, Equatable {
  let present: Bool
  let percentage: Double?
  let state: BatteryState
  let externalPowerConnected: Bool
  let timeRemainingMinutes: Int?
  let timeToFullMinutes: Int?
  let cycleCount: Int?
  let condition: String?
  let currentCapacityMah: Double?
  let maxCapacityMah: Double?
  let designCapacityMah: Double?
  let healthPercent: Double?
  let temperatureCelsius: Double?
  let voltageVolts: Double?
  let currentAmperes: Double?
  let batteryPowerWatts: Double?
}

nonisolated struct AdapterStats: Codable, Sendable, Equatable {
  let connected: Bool
  let manufacturer: String?
  let model: String?
  let transport: String?
  let ratedPowerWatts: Double?
  let voltageVolts: Double?
  let currentAmperes: Double?
  let measuredPowerWatts: Double?
}

nonisolated struct GPUStats: Codable, Sendable, Equatable {
  let name: String?
  let metalAvailable: Bool
  let registryID: UInt64?
  let hasUnifiedMemory: Bool?
  let isLowPower: Bool?
  let isRemovable: Bool?
  let recommendedWorkingSetBytes: UInt64?
  let systemUtilizationPercent: Double?
  let utilizationAvailability: MetricAvailability
}

nonisolated enum TemperatureSensorCategory: String, Codable, CaseIterable, Sendable {
  case processor
  case graphics
  case memory
  case storage
  case battery
  case power
  case enclosure
  case other

  var displayName: String {
    switch self {
    case .processor: return TemperatureL10n.string("Processor")
    case .graphics: return TemperatureL10n.string("Graphics")
    case .memory: return L10n.string("Memory")
    case .storage: return TemperatureL10n.string("Storage")
    case .battery: return L10n.string("Battery")
    case .power: return L10n.string("Power")
    case .enclosure: return TemperatureL10n.string("Enclosure")
    case .other: return TemperatureL10n.string("Other sensors")
    }
  }

  var symbolName: String {
    switch self {
    case .processor: return "cpu"
    case .graphics: return "rectangle.3.group"
    case .memory: return "memorychip"
    case .storage: return "internaldrive"
    case .battery: return "battery.75percent"
    case .power: return "bolt.fill"
    case .enclosure: return "laptopcomputer"
    case .other: return "thermometer.variable"
    }
  }
}

nonisolated struct TemperatureReading: Codable, Sendable, Equatable, Identifiable {
  let id: String
  let key: String?
  let name: String
  let category: TemperatureSensorCategory
  let celsius: Double
  let source: MetricSource
  let isPrimary: Bool

  init(
    id: String,
    key: String? = nil,
    name: String,
    category: TemperatureSensorCategory,
    celsius: Double,
    source: MetricSource,
    isPrimary: Bool = false
  ) {
    self.id = id
    self.key = key
    self.name = name
    self.category = category
    self.celsius = celsius
    self.source = source
    self.isPrimary = isPrimary
  }
}

nonisolated struct TemperatureStats: Codable, Sendable, Equatable {
  let processorCelsius: Double?
  let batteryCelsius: Double?
  let maximumCelsius: Double?
  let processorSensorKey: String?
  let sensors: [TemperatureReading]

  init(
    processorCelsius: Double?,
    batteryCelsius: Double?,
    maximumCelsius: Double?,
    processorSensorKey: String?,
    sensors: [TemperatureReading] = []
  ) {
    self.processorCelsius = processorCelsius
    self.batteryCelsius = batteryCelsius
    self.maximumCelsius = maximumCelsius
    self.processorSensorKey = processorSensorKey
    self.sensors = sensors
  }
}

nonisolated enum FanMode: String, Codable, Sendable {
  case automatic
  case system
  case manual
  case unknown

  static func decodeSMCByte(_ value: UInt8?) -> Self {
    switch value {
    case 0: return .automatic
    case 1: return .manual
    case 3: return .system
    default: return .unknown
    }
  }

  var isSystemControlled: Bool {
    self == .automatic || self == .system
  }
}

nonisolated struct FanReading: Codable, Sendable, Equatable, Identifiable {
  let index: Int
  let currentRPM: Double?
  let targetRPM: Double?
  let minimumRPM: Double?
  let maximumRPM: Double?
  let mode: FanMode

  var id: Int { index }
}

nonisolated struct FanStats: Codable, Sendable, Equatable {
  let fans: [FanReading]

  var count: Int { fans.count }
}

nonisolated enum PowerSufficiencyStatus: String, Codable, Sendable {
  case notConnected
  case sufficient
  case borderline
  case insufficient
  case chargingBattery
  case powerAdapterOnly
  case unknown
  case sensorConflict
}

nonisolated struct PowerAssessment: Codable, Sendable, Equatable {
  let status: PowerSufficiencyStatus
  let confidence: Double
  let batteryPowerWatts: Double?
  let estimatedSystemPowerWatts: Double?
  let powerBalanceWatts: Double?
  let explanation: String
  let adapterInputPowerWatts: Double?

  init(
    status: PowerSufficiencyStatus,
    confidence: Double,
    batteryPowerWatts: Double?,
    estimatedSystemPowerWatts: Double?,
    powerBalanceWatts: Double?,
    explanation: String,
    adapterInputPowerWatts: Double? = nil
  ) {
    self.status = status
    self.confidence = confidence
    self.batteryPowerWatts = batteryPowerWatts
    self.estimatedSystemPowerWatts = estimatedSystemPowerWatts
    self.powerBalanceWatts = powerBalanceWatts
    self.explanation = explanation
    self.adapterInputPowerWatts = adapterInputPowerWatts
  }
}

nonisolated struct SystemSnapshot: Codable, Sendable, Equatable {
  let timestamp: Date
  let cpu: MetricValue<CPUStats>
  let memory: MetricValue<MemoryStats>
  let battery: MetricValue<BatteryStats>
  let adapter: MetricValue<AdapterStats>
  let gpu: MetricValue<GPUStats>
  let temperature: MetricValue<TemperatureStats>
  let fans: MetricValue<FanStats>
  let power: MetricValue<PowerAssessment>

  init(
    timestamp: Date,
    cpu: MetricValue<CPUStats>,
    memory: MetricValue<MemoryStats>,
    battery: MetricValue<BatteryStats>,
    adapter: MetricValue<AdapterStats>,
    gpu: MetricValue<GPUStats>,
    temperature: MetricValue<TemperatureStats> = .unavailable(
      unit: .celsius,
      availability: .temporarilyUnavailable),
    fans: MetricValue<FanStats> = .unavailable(
      unit: .rpm,
      availability: .temporarilyUnavailable),
    power: MetricValue<PowerAssessment>
  ) {
    self.timestamp = timestamp
    self.cpu = cpu
    self.memory = memory
    self.battery = battery
    self.adapter = adapter
    self.gpu = gpu
    self.temperature = temperature
    self.fans = fans
    self.power = power
  }

  static let empty = SystemSnapshot(
    timestamp: Date(),
    cpu: .unavailable(unit: .percent, availability: .temporarilyUnavailable),
    memory: .unavailable(unit: .bytes, availability: .temporarilyUnavailable),
    battery: .unavailable(unit: .percent, availability: .temporarilyUnavailable),
    adapter: .unavailable(unit: .watts, availability: .temporarilyUnavailable),
    gpu: .unavailable(unit: .percent, availability: .temporarilyUnavailable),
    temperature: .unavailable(unit: .celsius, availability: .temporarilyUnavailable),
    fans: .unavailable(unit: .rpm, availability: .temporarilyUnavailable),
    power: .unavailable(unit: .watts, availability: .temporarilyUnavailable)
  )
}
