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
  @discardableResult
  func recordContinuous(snapshot: ProcessMetricsSnapshot, elapsed: TimeInterval) -> Bool {
    guard let elapsed = HistoricalConsumptionContinuityPolicy.recordingElapsed(elapsed) else {
      return false
    }
    record(snapshot: snapshot, elapsed: elapsed)
    return true
  }
}
