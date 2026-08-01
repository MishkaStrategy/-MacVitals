import Darwin
import Foundation

nonisolated enum HistoricalConsumptionMetric: String, CaseIterable, Sendable {
  case cpu
  case memory
  case gpu
  case energy
  case disk
  case thermal
  case network
}

nonisolated enum HistoricalConsumptionRange: String, CaseIterable, Identifiable, Sendable {
  case oneHour
  case twelveHours
  case oneDay
  case sevenDays

  var id: String { rawValue }

  var duration: TimeInterval {
    switch self {
    case .oneHour: return 60 * 60
    case .twelveHours: return 12 * 60 * 60
    case .oneDay: return 24 * 60 * 60
    case .sevenDays: return 7 * 24 * 60 * 60
    }
  }

  var title: String {
    switch self {
    case .oneHour: return ConsumptionHistoryL10n.string("1 h")
    case .twelveHours: return ConsumptionHistoryL10n.string("12 h")
    case .oneDay: return ConsumptionHistoryL10n.string("1 d")
    case .sevenDays: return ConsumptionHistoryL10n.string("7 d")
    }
  }
}

nonisolated struct HistoricalConsumptionLeader: Identifiable, Sendable, Equatable {
  let id: String
  let name: String
  let bundleIdentifier: String?
  let representativePID: pid_t
  let processCountPeak: Int
  let observedSeconds: Double
  let cpuCoreSeconds: Double
  let memoryByteSeconds: Double
  let memoryPeakBytes: UInt64
  let gpuScoreSeconds: Double
  let energyImpactScoreSeconds: Double
  let directEnergyJoules: Double
  let directEnergyObservedSeconds: Double
  let diskBytes: Double
  let thermalScoreSeconds: Double

  var averageMemoryBytes: UInt64 {
    guard observedSeconds > 0 else { return 0 }
    return UInt64(max(0, memoryByteSeconds / observedSeconds).rounded())
  }

  var averageGPUScore: Double {
    observedSeconds > 0 ? max(0, gpuScoreSeconds / observedSeconds) : 0
  }

  var averageEnergyImpact: Double {
    observedSeconds > 0 ? max(0, energyImpactScoreSeconds / observedSeconds) : 0
  }

  var averageThermalScore: Double {
    observedSeconds > 0 ? max(0, thermalScoreSeconds / observedSeconds) : 0
  }
}

nonisolated struct HistoricalConsumptionArchive: Codable, Sendable {
  var schemaVersion = 1
  var buckets: [HistoricalConsumptionBucket] = []
}

nonisolated struct HistoricalConsumptionBucket: Codable, Sendable {
  let startedAt: Date
  var applications: [String: HistoricalConsumptionAggregate]
}

nonisolated struct HistoricalConsumptionAggregate: Codable, Sendable {
  let id: String
  var name: String
  var bundleIdentifier: String?
  var representativePID: pid_t
  var processCountPeak: Int
  var observedSeconds: Double
  var cpuCoreSeconds: Double
  var memoryByteSeconds: Double
  var memoryPeakBytes: UInt64
  var gpuScoreSeconds: Double
  var energyImpactScoreSeconds: Double
  var directEnergyJoules: Double
  var directEnergyObservedSeconds: Double
  var diskBytes: Double
  var thermalScoreSeconds: Double

  init(application: ApplicationProcessUsage) {
    id = application.id
    name = application.name
    bundleIdentifier = application.bundleIdentifier
    representativePID = application.representativePID
    processCountPeak = application.processCount
    observedSeconds = 0
    cpuCoreSeconds = 0
    memoryByteSeconds = 0
    memoryPeakBytes = application.memoryBytes
    gpuScoreSeconds = 0
    energyImpactScoreSeconds = 0
    directEnergyJoules = 0
    directEnergyObservedSeconds = 0
    diskBytes = 0
    thermalScoreSeconds = 0
  }

  mutating func add(application: ApplicationProcessUsage, elapsed: TimeInterval) {
    name = application.name
    bundleIdentifier = application.bundleIdentifier ?? bundleIdentifier
    representativePID = application.representativePID
    processCountPeak = max(processCountPeak, application.processCount)
    observedSeconds += elapsed
    cpuCoreSeconds += max(0, application.cpuPercent) / 100 * elapsed
    memoryByteSeconds += Double(application.memoryBytes) * elapsed
    memoryPeakBytes = max(memoryPeakBytes, application.memoryBytes)
    gpuScoreSeconds += max(0, application.gpuActivityScore) * elapsed
    energyImpactScoreSeconds += max(0, application.energyImpactScore) * elapsed
    if let watts = application.energyWatts, watts.isFinite, watts >= 0 {
      directEnergyJoules += watts * elapsed
      directEnergyObservedSeconds += elapsed
    }
    diskBytes += max(0, application.diskBytesPerSecond) * elapsed
    thermalScoreSeconds += (
      max(0, application.cpuPercent) * 0.45
        + max(0, application.gpuActivityScore) * 0.35
        + max(0, application.energyImpactScore) * 0.20
    ) * elapsed
  }

  mutating func merge(_ other: HistoricalConsumptionAggregate) {
    name = other.name
    bundleIdentifier = other.bundleIdentifier ?? bundleIdentifier
    representativePID = other.representativePID
    processCountPeak = max(processCountPeak, other.processCountPeak)
    observedSeconds += other.observedSeconds
    cpuCoreSeconds += other.cpuCoreSeconds
    memoryByteSeconds += other.memoryByteSeconds
    memoryPeakBytes = max(memoryPeakBytes, other.memoryPeakBytes)
    gpuScoreSeconds += other.gpuScoreSeconds
    energyImpactScoreSeconds += other.energyImpactScoreSeconds
    directEnergyJoules += other.directEnergyJoules
    directEnergyObservedSeconds += other.directEnergyObservedSeconds
    diskBytes += other.diskBytes
    thermalScoreSeconds += other.thermalScoreSeconds
  }

  var leader: HistoricalConsumptionLeader {
    HistoricalConsumptionLeader(
      id: id,
      name: name,
      bundleIdentifier: bundleIdentifier,
      representativePID: representativePID,
      processCountPeak: processCountPeak,
      observedSeconds: observedSeconds,
      cpuCoreSeconds: cpuCoreSeconds,
      memoryByteSeconds: memoryByteSeconds,
      memoryPeakBytes: memoryPeakBytes,
      gpuScoreSeconds: gpuScoreSeconds,
      energyImpactScoreSeconds: energyImpactScoreSeconds,
      directEnergyJoules: directEnergyJoules,
      directEnergyObservedSeconds: directEnergyObservedSeconds,
      diskBytes: diskBytes,
      thermalScoreSeconds: thermalScoreSeconds)
  }

  func score(for metric: HistoricalConsumptionMetric) -> Double {
    switch metric {
    case .cpu: return cpuCoreSeconds
    case .memory: return memoryByteSeconds
    case .gpu: return gpuScoreSeconds
    case .energy: return energyImpactScoreSeconds
    case .disk: return diskBytes
    case .thermal: return thermalScoreSeconds
    case .network: return 0
    }
  }
}
