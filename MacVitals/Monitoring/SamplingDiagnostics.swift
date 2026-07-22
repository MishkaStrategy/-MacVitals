import Foundation

nonisolated struct SamplingTimings: Codable, Sendable, Equatable {
  let cpuMilliseconds: Double
  let memoryMilliseconds: Double
  let batteryMilliseconds: Double
  let adapterMilliseconds: Double
  let gpuMilliseconds: Double
  let powerModelMilliseconds: Double
  let totalMilliseconds: Double

  init(
    cpuMilliseconds: Double,
    memoryMilliseconds: Double,
    batteryMilliseconds: Double,
    adapterMilliseconds: Double,
    gpuMilliseconds: Double,
    powerModelMilliseconds: Double,
    totalMilliseconds: Double
  ) {
    self.cpuMilliseconds = Self.sanitize(cpuMilliseconds)
    self.memoryMilliseconds = Self.sanitize(memoryMilliseconds)
    self.batteryMilliseconds = Self.sanitize(batteryMilliseconds)
    self.adapterMilliseconds = Self.sanitize(adapterMilliseconds)
    self.gpuMilliseconds = Self.sanitize(gpuMilliseconds)
    self.powerModelMilliseconds = Self.sanitize(powerModelMilliseconds)
    self.totalMilliseconds = Self.sanitize(totalMilliseconds)
  }

  private static func sanitize(_ value: Double) -> Double {
    value.isFinite ? max(0, value) : 0
  }
}

nonisolated struct SamplingHealth: Codable, Sendable, Equatable {
  let timings: SamplingTimings
  let configuredIntervalSeconds: TimeInterval
  let overranInterval: Bool

  init(timings: SamplingTimings, configuredIntervalSeconds: TimeInterval) {
    let interval = max(0.5, configuredIntervalSeconds.isFinite ? configuredIntervalSeconds : 2)
    self.timings = timings
    self.configuredIntervalSeconds = interval
    overranInterval = timings.totalMilliseconds > interval * 1_000
  }
}

nonisolated struct SampleResult: Sendable, Equatable {
  let snapshot: SystemSnapshot
  let timings: SamplingTimings
}

nonisolated enum SamplingTimingMath {
  static func milliseconds(startNanoseconds: UInt64, endNanoseconds: UInt64) -> Double {
    guard endNanoseconds >= startNanoseconds else { return 0 }
    return Double(endNanoseconds - startNanoseconds) / 1_000_000
  }

  static func remainingDelaySeconds(
    intervalSeconds: TimeInterval,
    elapsedMilliseconds: Double,
    minimumDelaySeconds: TimeInterval = 0.05
  ) -> TimeInterval {
    let interval = max(0.5, intervalSeconds.isFinite ? intervalSeconds : 2)
    let elapsedSeconds = max(0, elapsedMilliseconds.isFinite ? elapsedMilliseconds / 1_000 : 0)
    return max(minimumDelaySeconds, interval - elapsedSeconds)
  }
}
