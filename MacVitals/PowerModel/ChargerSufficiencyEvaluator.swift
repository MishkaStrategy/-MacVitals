import Foundation

nonisolated struct PowerSample: Sendable, Equatable {
  let timestamp: Date
  let externalPower: Bool
  let batteryPowerWatts: Double?
  let adapterRatedPowerWatts: Double?
  let adapterMeasuredPowerWatts: Double?
  let batteryPercent: Double?
  let batteryTimestamp: Date?
  let adapterTimestamp: Date?

  init(
    timestamp: Date,
    externalPower: Bool,
    batteryPowerWatts: Double?,
    adapterRatedPowerWatts: Double?,
    adapterMeasuredPowerWatts: Double?,
    batteryPercent: Double?,
    batteryTimestamp: Date? = nil,
    adapterTimestamp: Date? = nil
  ) {
    self.timestamp = timestamp
    self.externalPower = externalPower
    self.batteryPowerWatts = batteryPowerWatts
    self.adapterRatedPowerWatts = adapterRatedPowerWatts
    self.adapterMeasuredPowerWatts = adapterMeasuredPowerWatts
    self.batteryPercent = batteryPercent
    self.batteryTimestamp = batteryTimestamp
    self.adapterTimestamp = adapterTimestamp
  }
}

nonisolated struct ChargerSufficiencyConfiguration: Sendable, Equatable {
  var insufficientDischargeWatts: Double
  var borderlineDischargeWatts: Double
  var hysteresisWatts: Double
  var confirmationDuration: TimeInterval
  var minimumSamples: Int
  var maximumTimestampSkew: TimeInterval
  var maximumPlausibleBatteryPowerWatts: Double

  init(
    insufficientDischargeWatts: Double = 2.0,
    borderlineDischargeWatts: Double = 0.5,
    hysteresisWatts: Double = 0.25,
    confirmationDuration: TimeInterval = 20,
    minimumSamples: Int = 5,
    maximumTimestampSkew: TimeInterval = 5,
    maximumPlausibleBatteryPowerWatts: Double = 250
  ) {
    self.insufficientDischargeWatts = max(0.1, insufficientDischargeWatts)
    self.borderlineDischargeWatts = max(
      0, min(borderlineDischargeWatts, insufficientDischargeWatts))
    self.hysteresisWatts = max(0, min(hysteresisWatts, insufficientDischargeWatts))
    self.confirmationDuration = max(0, confirmationDuration)
    self.minimumSamples = max(1, minimumSamples)
    self.maximumTimestampSkew = max(0, maximumTimestampSkew)
    self.maximumPlausibleBatteryPowerWatts = max(1, maximumPlausibleBatteryPowerWatts)
  }
}

nonisolated struct ChargerSufficiencyEvaluator: Sendable {
  private(set) var samples: [PowerSample] = []
  private(set) var lastStableStatus: PowerSufficiencyStatus = .unknown
  private var lastExternalPower: Bool?
  let configuration: ChargerSufficiencyConfiguration

  init(configuration: ChargerSufficiencyConfiguration = .init()) {
    self.configuration = configuration
  }

  mutating func reset() {
    samples.removeAll(keepingCapacity: true)
    lastStableStatus = .unknown
    lastExternalPower = nil
  }

  mutating func evaluate(_ sample: PowerSample) -> PowerAssessment {
    if let previousTimestamp = samples.last?.timestamp, sample.timestamp < previousTimestamp {
      reset()
    }

    if lastExternalPower != sample.externalPower {
      samples.removeAll(keepingCapacity: true)
      lastStableStatus = sample.externalPower ? .unknown : .notConnected
      lastExternalPower = sample.externalPower
    }

    samples.append(sample)
    trimHistory(relativeTo: sample.timestamp)

    guard sample.externalPower else {
      lastStableStatus = .notConnected
      return assessment(.notConnected, 1, sample, nil, "External power is not connected")
    }

    if let conflict = validationConflict(in: sample) {
      lastStableStatus = .sensorConflict
      return assessment(.sensorConflict, 0.1, sample, sample.batteryPowerWatts, conflict)
    }

    let windowStart = sample.timestamp.addingTimeInterval(-configuration.confirmationDuration)
    let window =
      samples
      .filter { $0.externalPower && $0.timestamp >= windowStart && $0.batteryPowerWatts != nil }
      .sorted { $0.timestamp < $1.timestamp }

    guard window.count >= configuration.minimumSamples else {
      let confidence = min(0.49, Double(window.count) / Double(configuration.minimumSamples) * 0.49)
      return assessment(
        .unknown,
        confidence,
        sample,
        nil,
        "Collecting enough battery-power samples"
      )
    }

    let observedDuration = window.last!.timestamp.timeIntervalSince(window.first!.timestamp)
    guard observedDuration >= configuration.confirmationDuration else {
      let durationFactor =
        configuration.confirmationDuration == 0
        ? 1
        : max(0, min(1, observedDuration / configuration.confirmationDuration))
      return assessment(
        .unknown,
        min(0.49, durationFactor * 0.49),
        sample,
        nil,
        "Waiting for the confirmation window to complete"
      )
    }

    let powers = window.compactMap(\.batteryPowerWatts).sorted()
    guard let medianPower = median(powers) else {
      return assessment(.unknown, 0, sample, nil, "Battery power direction is unavailable")
    }

    let status = classify(medianPower: medianPower, batteryPercent: sample.batteryPercent)
    lastStableStatus = status

    let countFactor = min(1, Double(window.count) / Double(max(configuration.minimumSamples, 10)))
    let durationFactor =
      configuration.confirmationDuration == 0
      ? 1
      : min(1, observedDuration / configuration.confirmationDuration)
    let confidence = max(0, min(1, 0.5 + 0.25 * countFactor + 0.25 * durationFactor))

    return assessment(
      status,
      confidence,
      sample,
      medianPower,
      explanation(status, medianPower)
    )
  }

  private mutating func trimHistory(relativeTo timestamp: Date) {
    let retention = max(60, configuration.confirmationDuration * 3)
    let cutoff = timestamp.addingTimeInterval(-retention)
    samples.removeAll { $0.timestamp < cutoff }
  }

  private func validationConflict(in sample: PowerSample) -> String? {
    if let percent = sample.batteryPercent, !(0...100).contains(percent) {
      return "Battery percentage is outside the valid range"
    }
    if let power = sample.batteryPowerWatts,
      !power.isFinite || abs(power) > configuration.maximumPlausibleBatteryPowerWatts
    {
      return "Battery power is outside the plausible range"
    }
    if let measured = sample.adapterMeasuredPowerWatts, !measured.isFinite || measured < 0 {
      return "Measured adapter power is invalid"
    }
    if let rated = sample.adapterRatedPowerWatts, !rated.isFinite || rated <= 0 {
      return "Rated adapter power is invalid"
    }
    return nil
  }

  private func classify(medianPower: Double, batteryPercent: Double?) -> PowerSufficiencyStatus {
    let insufficientThreshold = configuration.insufficientDischargeWatts
    let borderlineThreshold = configuration.borderlineDischargeWatts
    let hysteresis = configuration.hysteresisWatts

    if lastStableStatus == .insufficient,
      medianPower <= -(insufficientThreshold - hysteresis)
    {
      return .insufficient
    }

    if lastStableStatus == .chargingBattery,
      medianPower >= max(0, borderlineThreshold - hysteresis)
    {
      return .chargingBattery
    }

    if medianPower <= -insufficientThreshold {
      return .insufficient
    }
    if medianPower < -borderlineThreshold {
      return .borderline
    }
    if medianPower > borderlineThreshold {
      return .chargingBattery
    }
    if let batteryPercent, batteryPercent >= 99.5 {
      return .powerAdapterOnly
    }
    return .sufficient
  }

  private func assessment(
    _ status: PowerSufficiencyStatus,
    _ confidence: Double,
    _ sample: PowerSample,
    _ medianBatteryPower: Double?,
    _ explanation: String
  ) -> PowerAssessment {
    let timestampsAligned = timestampsAreAligned(in: sample)
    let systemPower: Double?
    if timestampsAligned,
      let measured = sample.adapterMeasuredPowerWatts,
      let battery = medianBatteryPower
    {
      systemPower = max(0, measured - battery)
    } else {
      systemPower = nil
    }

    let alignmentNote =
      timestampsAligned
      ? ""
      : " Adapter and battery samples were not aligned, so system power was not estimated."

    return PowerAssessment(
      status: status,
      confidence: confidence,
      batteryPowerWatts: medianBatteryPower,
      estimatedSystemPowerWatts: systemPower,
      powerBalanceWatts: nil,
      explanation: explanation + alignmentNote
    )
  }

  private func timestampsAreAligned(in sample: PowerSample) -> Bool {
    guard sample.adapterMeasuredPowerWatts != nil else { return true }
    let batteryTimestamp = sample.batteryTimestamp ?? sample.timestamp
    let adapterTimestamp = sample.adapterTimestamp ?? sample.timestamp
    return abs(batteryTimestamp.timeIntervalSince(adapterTimestamp))
      <= configuration.maximumTimestampSkew
  }

  private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let middle = values.count / 2
    if values.count.isMultiple(of: 2) {
      return (values[middle - 1] + values[middle]) / 2
    }
    return values[middle]
  }

  private func explanation(_ status: PowerSufficiencyStatus, _ power: Double) -> String {
    switch status {
    case .insufficient:
      return
        "Battery is continuously discharging while external power is connected (median \(String(format: "%.1f", power)) W)"
    case .borderline:
      return "Power is near the configured boundary"
    case .chargingBattery:
      return "External power supports the system and charges the battery"
    case .powerAdapterOnly:
      return "The Mac is on adapter power and the battery is effectively full"
    case .sufficient:
      return "No sustained battery discharge is detected"
    default:
      return "Power state cannot be determined"
    }
  }
}
