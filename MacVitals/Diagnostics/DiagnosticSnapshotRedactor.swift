import Foundation

nonisolated enum DiagnosticSnapshotRedactor {
  static func redact(_ snapshot: SystemSnapshot) -> SystemSnapshot {
    SystemSnapshot(
      timestamp: snapshot.timestamp,
      cpu: snapshot.cpu,
      memory: snapshot.memory,
      battery: snapshot.battery,
      adapter: snapshot.adapter,
      gpu: redactedGPU(snapshot.gpu),
      power: snapshot.power)
  }

  private static func redactedGPU(
    _ metric: MetricValue<GPUStats>
  ) -> MetricValue<GPUStats> {
    guard let value = metric.value else { return metric }
    let redacted = GPUStats(
      name: value.name,
      metalAvailable: value.metalAvailable,
      registryID: nil,
      hasUnifiedMemory: value.hasUnifiedMemory,
      isLowPower: value.isLowPower,
      isRemovable: value.isRemovable,
      recommendedWorkingSetBytes: value.recommendedWorkingSetBytes,
      systemUtilizationPercent: value.systemUtilizationPercent,
      utilizationAvailability: value.utilizationAvailability)
    return MetricValue(
      value: redacted,
      unit: metric.unit,
      availability: metric.availability,
      quality: metric.quality,
      source: metric.source,
      timestamp: metric.timestamp,
      isEstimated: metric.isEstimated,
      message: metric.message)
  }
}
