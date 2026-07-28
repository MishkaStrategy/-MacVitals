import Darwin
import Foundation

nonisolated enum ProcessConsumerMetric: String, CaseIterable, Sendable {
  case cpu
  case memory
  case gpu
  case energy
}

nonisolated struct ApplicationProcessUsage: Identifiable, Sendable, Equatable {
  let id: String
  let name: String
  let bundleIdentifier: String?
  let iconPath: String?
  let processCount: Int
  let cpuPercent: Double
  let memoryBytes: UInt64
  let energyWatts: Double?
  let energyImpactScore: Double
  let gpuActivityScore: Double
  let diskBytesPerSecond: Double
  let isGPUActivityEstimated: Bool
  let isEnergyEstimated: Bool
}

nonisolated struct ProcessMetricsSnapshot: Sendable, Equatable {
  let timestamp: Date
  let applications: [ApplicationProcessUsage]
  let sampledProcessCount: Int
  let energyCountersAvailable: Bool

  static let empty = ProcessMetricsSnapshot(
    timestamp: .distantPast,
    applications: [],
    sampledProcessCount: 0,
    energyCountersAvailable: false)
}

nonisolated struct ProcessCounterSample: Sendable, Equatable {
  let pid: pid_t
  let startTime: UInt64
  let name: String
  let executablePath: String?
  let cpuTimeNanoseconds: UInt64
  let physicalFootprintBytes: UInt64
  let energyNanojoules: UInt64?
  let diskReadBytes: UInt64?
  let diskWriteBytes: UInt64?
}

nonisolated struct ProcessCounterDelta: Sendable, Equatable {
  let cpuPercent: Double
  let energyWatts: Double?
  let diskBytesPerSecond: Double
}

nonisolated enum ProcessCounterCalculator {
  static func delta(
    previous: ProcessCounterSample?,
    current: ProcessCounterSample,
    elapsedSeconds: TimeInterval
  ) -> ProcessCounterDelta {
    guard let previous,
      previous.pid == current.pid,
      previous.startTime == current.startTime,
      elapsedSeconds.isFinite,
      elapsedSeconds > 0
    else {
      return ProcessCounterDelta(cpuPercent: 0, energyWatts: nil, diskBytesPerSecond: 0)
    }

    let cpuDelta = monotonicDelta(previous.cpuTimeNanoseconds, current.cpuTimeNanoseconds)
    let cpuPercent = min(
      10_000,
      max(0, Double(cpuDelta) / 1_000_000_000 / elapsedSeconds * 100))

    let energyWatts: Double?
    if let oldEnergy = previous.energyNanojoules,
      let newEnergy = current.energyNanojoules,
      newEnergy >= oldEnergy
    {
      let joules = Double(newEnergy - oldEnergy) / 1_000_000_000
      let watts = joules / elapsedSeconds
      energyWatts = watts.isFinite && watts >= 0 ? watts : nil
    } else {
      energyWatts = nil
    }

    let oldDisk = (previous.diskReadBytes ?? 0) &+ (previous.diskWriteBytes ?? 0)
    let newDisk = (current.diskReadBytes ?? 0) &+ (current.diskWriteBytes ?? 0)
    let diskDelta = monotonicDelta(oldDisk, newDisk)
    let diskRate = max(0, Double(diskDelta) / elapsedSeconds)

    return ProcessCounterDelta(
      cpuPercent: cpuPercent,
      energyWatts: energyWatts,
      diskBytesPerSecond: diskRate.isFinite ? diskRate : 0)
  }

  static func normalizedScores(_ values: [Double]) -> [Double] {
    let sanitized = values.map { $0.isFinite ? max(0, $0) : 0 }
    guard let maximum = sanitized.max(), maximum > 0 else {
      return Array(repeating: 0, count: values.count)
    }
    return sanitized.map { min(100, max(0, $0 / maximum * 100)) }
  }

  private static func monotonicDelta(_ previous: UInt64, _ current: UInt64) -> UInt64 {
    current >= previous ? current - previous : 0
  }
}

actor ProcessMetricsProvider {
  private struct ProcessIdentity: Hashable {
    let pid: pid_t
    let startTime: UInt64
  }

  private struct ApplicationDescriptor: Sendable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let iconPath: String?
  }

  private struct ApplicationAccumulator {
    let descriptor: ApplicationDescriptor
    var processCount = 0
    var cpuPercent = 0.0
    var memoryBytes: UInt64 = 0
    var energyWatts = 0.0
    var hasEnergy = false
    var diskBytesPerSecond = 0.0
    var graphicsSignal = 0.0
  }

  private var previousTimestamp: Date?
  private var previousSamples: [ProcessIdentity: ProcessCounterSample] = [:]

  func reset() {
    previousTimestamp = nil
    previousSamples.removeAll(keepingCapacity: true)
  }

  func sample() -> ProcessMetricsSnapshot {
    let now = Date()
    let samples = readAllProcesses()
    let elapsed = previousTimestamp.map { now.timeIntervalSince($0) } ?? 0
    var accumulators: [String: ApplicationAccumulator] = [:]
    var energyCountersAvailable = false

    for sample in samples {
      let identity = ProcessIdentity(pid: sample.pid, startTime: sample.startTime)
      let counters = ProcessCounterCalculator.delta(
        previous: previousSamples[identity],
        current: sample,
        elapsedSeconds: elapsed)
      let descriptor = applicationDescriptor(for: sample)
      var accumulator = accumulators[descriptor.id]
        ?? ApplicationAccumulator(descriptor: descriptor)

      accumulator.processCount += 1
      accumulator.cpuPercent += counters.cpuPercent
      accumulator.memoryBytes = accumulator.memoryBytes &+ sample.physicalFootprintBytes
      accumulator.diskBytesPerSecond += counters.diskBytesPerSecond
      if let watts = counters.energyWatts {
        accumulator.energyWatts += watts
        accumulator.hasEnergy = true
        energyCountersAvailable = true
      }
      accumulator.graphicsSignal += graphicsSignal(for: sample)
      accumulators[descriptor.id] = accumulator
    }

    previousTimestamp = now
    previousSamples = Dictionary(
      uniqueKeysWithValues: samples.map {
        (ProcessIdentity(pid: $0.pid, startTime: $0.startTime), $0)
      })

    let ordered = accumulators.values.sorted {
      if $0.cpuPercent == $1.cpuPercent {
        return $0.descriptor.name.localizedCaseInsensitiveCompare($1.descriptor.name)
          == .orderedAscending
      }
      return $0.cpuPercent > $1.cpuPercent
    }

    let energyRaw = ordered.map { accumulator -> Double in
      if accumulator.hasEnergy { return accumulator.energyWatts }
      let memoryGiB = Double(accumulator.memoryBytes) / 1_073_741_824
      let ioMiB = accumulator.diskBytesPerSecond / 1_048_576
      return accumulator.cpuPercent * 0.7 + memoryGiB * 3 + ioMiB * 1.5
    }
    let gpuRaw = ordered.map { accumulator -> Double in
      let accountedEnergy = accumulator.hasEnergy ? accumulator.energyWatts : 0
      let cpuComponent = accumulator.cpuPercent * 0.08
      let ioComponent = accumulator.diskBytesPerSecond / 1_048_576 * 0.04
      let graphicsMultiplier = accumulator.graphicsSignal > 0 ? 1 + accumulator.graphicsSignal : 0.18
      return max(0, (accountedEnergy * 3 + cpuComponent + ioComponent) * graphicsMultiplier)
    }
    let energyScores = ProcessCounterCalculator.normalizedScores(energyRaw)
    let gpuScores = ProcessCounterCalculator.normalizedScores(gpuRaw)

    let applications = ordered.indices.map { index in
      let accumulator = ordered[index]
      return ApplicationProcessUsage(
        id: accumulator.descriptor.id,
        name: accumulator.descriptor.name,
        bundleIdentifier: accumulator.descriptor.bundleIdentifier,
        iconPath: accumulator.descriptor.iconPath,
        processCount: accumulator.processCount,
        cpuPercent: accumulator.cpuPercent,
        memoryBytes: accumulator.memoryBytes,
        energyWatts: accumulator.hasEnergy ? accumulator.energyWatts : nil,
        energyImpactScore: energyScores[index],
        gpuActivityScore: gpuScores[index],
        diskBytesPerSecond: accumulator.diskBytesPerSecond,
        isGPUActivityEstimated: true,
        isEnergyEstimated: !accumulator.hasEnergy)
    }

    return ProcessMetricsSnapshot(
      timestamp: now,
      applications: applications,
      sampledProcessCount: samples.count,
      energyCountersAvailable: energyCountersAvailable)
  }

  private func readAllProcesses() -> [ProcessCounterSample] {
    let requestedCount = max(512, Int(proc_listallpids(nil, 0)) + 64)
    var pids = [pid_t](repeating: 0, count: requestedCount)
    let returned = pids.withUnsafeMutableBytes { buffer -> Int32 in
      proc_listallpids(buffer.baseAddress, Int32(buffer.count))
    }
    guard returned > 0 else { return [] }

    return pids.prefix(Int(returned)).compactMap { pid in
      guard pid > 0 else { return nil }
      return readProcess(pid: pid)
    }
  }

  private func readProcess(pid: pid_t) -> ProcessCounterSample? {
    var usage = rusage_info_v6()
    let usageResult: Int32 = withUnsafeMutablePointer(to: &usage) { pointer in
      var rawPointer: rusage_info_t? = UnsafeMutableRawPointer(pointer)
      return proc_pid_rusage(pid, RUSAGE_INFO_V6, &rawPointer)
    }

    var taskInfo = proc_taskinfo()
    let expectedTaskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
    let taskResult = withUnsafeMutablePointer(to: &taskInfo) { pointer in
      proc_pidinfo(pid, PROC_PIDTASKINFO, 0, pointer, expectedTaskSize)
    }

    guard usageResult == 0 || taskResult == expectedTaskSize else { return nil }

    let name = processName(pid: pid)
    let path = processPath(pid: pid)
    let cpuTime: UInt64
    let footprint: UInt64
    let startTime: UInt64
    let energy: UInt64?
    let diskRead: UInt64?
    let diskWrite: UInt64?

    if usageResult == 0 {
      cpuTime = usage.ri_user_time &+ usage.ri_system_time
      footprint = usage.ri_phys_footprint
      startTime = usage.ri_proc_start_abstime
      energy = usage.ri_energy_nj > 0 ? usage.ri_energy_nj : nil
      diskRead = usage.ri_diskio_bytesread
      diskWrite = usage.ri_diskio_byteswritten
    } else {
      cpuTime = taskInfo.pti_total_user &+ taskInfo.pti_total_system
      footprint = taskInfo.pti_resident_size
      startTime = 0
      energy = nil
      diskRead = nil
      diskWrite = nil
    }

    return ProcessCounterSample(
      pid: pid,
      startTime: startTime,
      name: name,
      executablePath: path,
      cpuTimeNanoseconds: cpuTime,
      physicalFootprintBytes: footprint,
      energyNanojoules: energy,
      diskReadBytes: diskRead,
      diskWriteBytes: diskWrite)
  }

  private func processName(pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
    let length = buffer.withUnsafeMutableBytes { bytes -> Int32 in
      proc_name(pid, bytes.baseAddress, UInt32(bytes.count))
    }
    guard length > 0 else { return L10n.string("Unknown process") }
    return buffer.withUnsafeBufferPointer { pointer in
      guard let base = pointer.baseAddress else { return L10n.string("Unknown process") }
      return String(cString: base)
    }
  }

  private func processPath(pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4_096)
    let length = buffer.withUnsafeMutableBytes { bytes -> Int32 in
      proc_pidpath(pid, bytes.baseAddress, UInt32(bytes.count))
    }
    guard length > 0 else { return nil }
    return buffer.withUnsafeBufferPointer { pointer in
      guard let base = pointer.baseAddress else { return nil }
      return String(cString: base)
    }
  }

  private func applicationDescriptor(for sample: ProcessCounterSample) -> ApplicationDescriptor {
    if let appPath = applicationBundlePath(from: sample.executablePath) {
      let bundle = Bundle(path: appPath)
      let bundleID = bundle?.bundleIdentifier
      let displayName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
      return ApplicationDescriptor(
        id: bundleID ?? appPath,
        name: displayName,
        bundleIdentifier: bundleID,
        iconPath: appPath)
    }

    let path = sample.executablePath
    return ApplicationDescriptor(
      id: path ?? "process:\(sample.name)",
      name: sample.name,
      bundleIdentifier: nil,
      iconPath: path)
  }

  private func applicationBundlePath(from executablePath: String?) -> String? {
    guard let executablePath else { return nil }
    let components = executablePath.split(separator: "/", omittingEmptySubsequences: true)
    var current = ""
    for component in components {
      current += "/\(component)"
      if component.lowercased().hasSuffix(".app") { return current }
    }
    return nil
  }

  private func graphicsSignal(for sample: ProcessCounterSample) -> Double {
    let haystack = "\(sample.name) \(sample.executablePath ?? "")".lowercased()
    let strongKeywords = ["gpu", "metal", "coreanimation", "windowserver", "webkit.gpu"]
    if strongKeywords.contains(where: haystack.contains) { return 1.25 }
    let moderateKeywords = ["renderer", "render", "webcontent", "video", "media"]
    if moderateKeywords.contains(where: haystack.contains) { return 0.55 }
    return 0
  }
}
