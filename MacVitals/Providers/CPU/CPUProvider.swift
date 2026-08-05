import Darwin.Mach
import Foundation

nonisolated struct CPUTicks: Equatable, Sendable {
  let user: UInt64
  let system: UInt64
  let idle: UInt64
  let nice: UInt64
}

nonisolated enum CPUCalculationError: Error {
  case zeroDelta
  case counterReset
}

nonisolated enum CPUUsageCalculator {
  static func calculate(previous: CPUTicks, current: CPUTicks) throws -> CPUStats {
    guard current.user >= previous.user,
      current.system >= previous.system,
      current.idle >= previous.idle,
      current.nice >= previous.nice
    else { throw CPUCalculationError.counterReset }

    let user = Double(current.user - previous.user)
    let system = Double(current.system - previous.system)
    let idle = Double(current.idle - previous.idle)
    let nice = Double(current.nice - previous.nice)
    let total = user + system + idle + nice
    guard total.isFinite, total > 0 else { throw CPUCalculationError.zeroDelta }

    func percent(_ value: Double) -> Double {
      min(100, max(0, value / total * 100))
    }

    let userPercent = percent(user + nice)
    let systemPercent = percent(system)
    let idlePercent = percent(idle)
    return CPUStats(
      total: min(100, max(0, userPercent + systemPercent)),
      user: userPercent,
      system: systemPercent,
      idle: idlePercent,
      logicalProcessors: ProcessInfo.processInfo.processorCount,
      activeProcessors: ProcessInfo.processInfo.activeProcessorCount)
  }
}

final class CPUProvider: @unchecked Sendable {
  private var previous: CPUTicks?
  private let lock = NSLock()
  private let hostPort: MachHostPortLease

  init(hostPort: MachHostPortLease = .shared) {
    self.hostPort = hostPort
  }

  func resetBaseline() { lock.withLock { previous = nil } }

  func sample() -> MetricValue<CPUStats> {
    let now = Date()
    guard let ticks = readTicks() else {
      return .unavailable(
        unit: .percent,
        availability: .providerError,
        source: .machHostStatistics,
        message: "host_statistics failed")
    }
    return lock.withLock {
      defer { previous = ticks }
      guard let previous else {
        return .unavailable(
          unit: .percent,
          availability: .temporarilyUnavailable,
          source: .machHostStatistics,
          message: "Collecting baseline")
      }
      do {
        let stats = try CPUUsageCalculator.calculate(previous: previous, current: ticks)
        return MetricValue(
          value: stats,
          unit: .percent,
          availability: .available,
          quality: .direct,
          source: .machHostStatistics,
          timestamp: now,
          isEstimated: false,
          message: nil)
      } catch {
        return .unavailable(
          unit: .percent,
          availability: .temporarilyUnavailable,
          source: .machHostStatistics,
          message: "CPU counters reset")
      }
    }
  }

  private func readTicks() -> CPUTicks? {
    var load = host_cpu_load_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &load) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(hostPort.name, HOST_CPU_LOAD_INFO, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return CPUTicks(
      user: UInt64(load.cpu_ticks.0),
      system: UInt64(load.cpu_ticks.1),
      idle: UInt64(load.cpu_ticks.2),
      nice: UInt64(load.cpu_ticks.3))
  }
}
