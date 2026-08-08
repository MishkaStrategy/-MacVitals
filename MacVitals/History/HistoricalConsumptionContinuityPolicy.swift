import Foundation

nonisolated enum HistoricalConsumptionContinuityPolicy {
  static let maximumContinuousElapsed: TimeInterval = 60

  static func recordingElapsed(_ elapsed: TimeInterval) -> TimeInterval? {
    guard elapsed.isFinite,
      elapsed > 0.25,
      elapsed <= maximumContinuousElapsed
    else {
      return nil
    }
    return elapsed
  }
}

extension HistoricalConsumptionArchiveStore {
  func recordContinuous(snapshot: ProcessMetricsSnapshot, elapsed: TimeInterval) {
    guard let elapsed = HistoricalConsumptionContinuityPolicy.recordingElapsed(elapsed) else {
      return
    }
    record(snapshot: snapshot, elapsed: elapsed)
  }
}
