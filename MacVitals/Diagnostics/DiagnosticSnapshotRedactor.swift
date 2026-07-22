import Foundation

nonisolated enum DiagnosticSnapshotRedactor {
  static func redact(_ snapshot: SystemSnapshot) -> SystemSnapshot {
    SystemSnapshot(
      timestamp: validDate(snapshot.timestamp),
      cpu: sanitizedCPU(snapshot.cpu),
      memory: sanitizedMemory(snapshot.memory),
      battery: sanitizedBattery(snapshot.battery),
      adapter: sanitizedAdapter(snapshot.adapter),
      gpu: sanitizedGPU(snapshot.gpu),
      power: sanitizedPower(snapshot.power))
  }

  private static func sanitizedCPU(
    _ metric: MetricValue<CPUStats>
  ) -> MetricValue<CPUStats> {
    guard let value = metric.value else { return sanitizedMetadata(metric) }
    guard validPercentage(value.total) != nil,
      validPercentage(value.user) != nil,
      validPercentage(value.system) != nil,
      validPercentage(value.idle) != nil,
      value.logicalProcessors >= 0,
      value.activeProcessors >= 0,
      value.activeProcessors <= value.logicalProcessors
    else {
      return invalidMetric(metric, message: "Invalid CPU telemetry was omitted")
    }
    return replacingValue(metric, value)
  }

  private static func sanitizedMemory(
    _ metric: MetricValue<MemoryStats>
  ) -> MetricValue<MemoryStats> {
    guard let value = metric.value else { return sanitizedMetadata(metric) }
    guard let usedPercent = validPercentage(value.usedPercent) else {
      return invalidMetric(metric, message: "Invalid memory telemetry was omitted")
    }
    let sanitized = MemoryStats(
      physicalBytes: value.physicalBytes,
      usedBytes: value.usedBytes,
      freeBytes: value.freeBytes,
      availableBytes: value.availableBytes,
      activeBytes: value.activeBytes,
      inactiveBytes: value.inactiveBytes,
      wiredBytes: value.wiredBytes,
      compressedBytes: value.compressedBytes,
      purgeableBytes: value.purgeableBytes,
      speculativeBytes: value.speculativeBytes,
      swapTotalBytes: value.swapTotalBytes,
      swapUsedBytes: value.swapUsedBytes,
      swapFreeBytes: value.swapFreeBytes,
      pressureLevel: value.pressureLevel,
      usedPercent: usedPercent)
    return replacingValue(metric, sanitized)
  }

  private static func sanitizedBattery(
    _ metric: MetricValue<BatteryStats>
  ) -> MetricValue<BatteryStats> {
    guard let value = metric.value else { return sanitizedMetadata(metric) }
    let sanitized = BatteryStats(
      present: value.present,
      percentage: validPercentage(value.percentage),
      state: value.state,
      externalPowerConnected: value.externalPowerConnected,
      timeRemainingMinutes: nonnegative(value.timeRemainingMinutes),
      timeToFullMinutes: nonnegative(value.timeToFullMinutes),
      cycleCount: nonnegative(value.cycleCount),
      condition: value.condition,
      currentCapacityMah: nonnegativeFinite(value.currentCapacityMah),
      maxCapacityMah: nonnegativeFinite(value.maxCapacityMah),
      designCapacityMah: nonnegativeFinite(value.designCapacityMah),
      healthPercent: validPercentage(value.healthPercent),
      temperatureCelsius: finite(value.temperatureCelsius),
      voltageVolts: nonnegativeFinite(value.voltageVolts),
      currentAmperes: finite(value.currentAmperes),
      batteryPowerWatts: finite(value.batteryPowerWatts))
    return replacingValue(metric, sanitized)
  }

  private static func sanitizedAdapter(
    _ metric: MetricValue<AdapterStats>
  ) -> MetricValue<AdapterStats> {
    guard let value = metric.value else { return sanitizedMetadata(metric) }
    let sanitized = AdapterStats(
      connected: value.connected,
      manufacturer: value.manufacturer,
      model: value.model,
      transport: value.transport,
      ratedPowerWatts: positiveFinite(value.ratedPowerWatts),
      voltageVolts: nonnegativeFinite(value.voltageVolts),
      currentAmperes: finite(value.currentAmperes),
      measuredPowerWatts: nonnegativeFinite(value.measuredPowerWatts))
    return replacingValue(metric, sanitized)
  }

  private static func sanitizedGPU(
    _ metric: MetricValue<GPUStats>
  ) -> MetricValue<GPUStats> {
    guard let value = metric.value else { return sanitizedMetadata(metric) }
    let sanitized = GPUStats(
      name: value.name,
      metalAvailable: value.metalAvailable,
      registryID: nil,
      hasUnifiedMemory: value.hasUnifiedMemory,
      isLowPower: value.isLowPower,
      isRemovable: value.isRemovable,
      recommendedWorkingSetBytes: value.recommendedWorkingSetBytes,
      systemUtilizationPercent: validPercentage(value.systemUtilizationPercent),
      utilizationAvailability: value.utilizationAvailability)
    return replacingValue(metric, sanitized)
  }

  private static func sanitizedPower(
    _ metric: MetricValue<PowerAssessment>
  ) -> MetricValue<PowerAssessment> {
    guard let value = metric.value else { return sanitizedMetadata(metric) }
    guard let confidence = finite(value.confidence), (0...1).contains(confidence) else {
      return invalidMetric(metric, message: "Invalid power assessment was omitted")
    }
    let sanitized = PowerAssessment(
      status: value.status,
      confidence: confidence,
      batteryPowerWatts: finite(value.batteryPowerWatts),
      estimatedSystemPowerWatts: nonnegativeFinite(value.estimatedSystemPowerWatts),
      powerBalanceWatts: finite(value.powerBalanceWatts),
      explanation: value.explanation)
    return replacingValue(metric, sanitized)
  }

  private static func sanitizedMetadata<Value>(
    _ metric: MetricValue<Value>
  ) -> MetricValue<Value> where Value: Codable & Sendable & Equatable {
    MetricValue(
      value: metric.value,
      unit: metric.unit,
      availability: metric.availability,
      quality: metric.quality,
      source: metric.source,
      timestamp: validDate(metric.timestamp),
      isEstimated: metric.isEstimated,
      message: metric.message)
  }

  private static func replacingValue<Value>(
    _ metric: MetricValue<Value>,
    _ value: Value
  ) -> MetricValue<Value> where Value: Codable & Sendable & Equatable {
    MetricValue(
      value: value,
      unit: metric.unit,
      availability: metric.availability,
      quality: metric.quality,
      source: metric.source,
      timestamp: validDate(metric.timestamp),
      isEstimated: metric.isEstimated,
      message: metric.message)
  }

  private static func invalidMetric<Value>(
    _ metric: MetricValue<Value>,
    message: String
  ) -> MetricValue<Value> where Value: Codable & Sendable & Equatable {
    MetricValue(
      value: nil,
      unit: metric.unit,
      availability: .providerError,
      quality: .unknown,
      source: metric.source,
      timestamp: validDate(metric.timestamp),
      isEstimated: false,
      message: message)
  }

  private static func validDate(_ value: Date) -> Date {
    value.timeIntervalSinceReferenceDate.isFinite
      ? value
      : Date(timeIntervalSinceReferenceDate: 0)
  }

  private static func finite(_ value: Double?) -> Double? {
    guard let value, value.isFinite else { return nil }
    return value
  }

  private static func validPercentage(_ value: Double?) -> Double? {
    guard let value = finite(value), (0...100).contains(value) else { return nil }
    return value
  }

  private static func positiveFinite(_ value: Double?) -> Double? {
    guard let value = finite(value), value > 0 else { return nil }
    return value
  }

  private static func nonnegativeFinite(_ value: Double?) -> Double? {
    guard let value = finite(value), value >= 0 else { return nil }
    return value
  }

  private static func nonnegative(_ value: Int?) -> Int? {
    guard let value, value >= 0 else { return nil }
    return value
  }
}