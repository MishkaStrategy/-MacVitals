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
  static let defaultInsufficientDischargeWatts = 2.0
  static let defaultBorderlineDischargeWatts = 0.5
  static let defaultHysteresisWatts = 0.25
  static let defaultConfirmationDuration: TimeInterval = 20
  static let defaultMinimumSamples = 5
  static let defaultMaximumTimestampSkew: TimeInterval = 5
  static let defaultMaximumPlausibleBatteryPowerWatts = 250.0
  static let defaultMaximumPlausibleAdapterPowerWatts = 10_000.0

  var insufficientDischargeWatts: Double
  var borderlineDischargeWatts: Double
  var hysteresisWatts: Double
  var confirmationDuration: TimeInterval
  var minimumSamples: Int
  var maximumTimestampSkew: TimeInterval
  var maximumPlausibleBatteryPowerWatts: Double
  var maximumPlausibleAdapterPowerWatts: Double

  init(
    insufficientDischargeWatts: Double = defaultInsufficientDischargeWatts,
    borderlineDischargeWatts: Double = defaultBorderlineDischargeWatts,
    hysteresisWatts: Double = defaultHysteresisWatts,
    confirmationDuration: TimeInterval = defaultConfirmationDuration,
    minimumSamples: Int = defaultMinimumSamples,
    maximumTimestampSkew: TimeInterval = defaultMaximumTimestampSkew,
    maximumPlausibleBatteryPowerWatts: Double = defaultMaximumPlausibleBatteryPowerWatts,
    maximumPlausibleAdapterPowerWatts: Double = defaultMaximumPlausibleAdapterPowerWatts
  ) {
    let insufficient = Self.bounded(
      insufficientDischargeWatts,
      defaultValue: Self.defaultInsufficientDischargeWatts,
      range: 0.1...10_000)
    self.insufficientDischargeWatts = insufficient
    self.borderlineDischargeWatts = Self.bounded(
      borderlineDischargeWatts,
      defaultValue: Self.defaultBorderlineDischargeWatts,
      range: 0...insufficient)
    self.hysteresisWatts = Self.bounded(
      hysteresisWatts,
      defaultValue: Self.defaultHysteresisWatts,
      range: 0...insufficient)
    self.confirmationDuration = Self.bounded(
      confirmationDuration,
      defaultValue: Self.defaultConfirmationDuration,
      range: 0...(24 * 60 * 60))
    self.minimumSamples = min(10_000, max(1, minimumSamples))
    self.maximumTimestampSkew = Self.bounded(
      maximumTimestampSkew,
      defaultValue: Self.defaultMaximumTimestampSkew,
      range: 0...3_600)
    self.maximumPlausibleBatteryPowerWatts = Self.bounded(
      maximumPlausibleBatteryPowerWatts,
      defaultValue: Self.defaultMaximumPlausibleBatteryPowerWatts,
      range: 1...10_000)
    self.maximumPlausibleAdapterPowerWatts = Self.bounded(
      maximumPlausibleAdapterPowerWatts,
      defaultValue: Self.defaultMaximumPlausibleAdapterPowerWatts,
      range: 1...100_000)
  }

  private static func bounded(
    _ value: Double,
    defaultValue: Double,
    range: ClosedRange<Double>
  ) -> Double {
    guard value.isFinite else { return defaultValue }
    return min(range.upperBound, max(range.lowerBound, value))
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

    guard sample.externalPower else {
      lastStableStatus = .notConnected
      return assessment(
        .notConnected,
        1,
        sample,
        nil,
        L10n.string("External power is not connected"))
    }

    if let conflict = validationConflict(in: sample) {
      samples.removeAll(keepingCapacity: true)
      lastStableStatus = .sensorConflict
      return assessment(.sensorConflict, 0.1, sample, nil, conflict)
    }

    samples.append(sample)
    trimHistory(relativeTo: sample.timestamp)

    let windowStart = sample.timestamp.addingTimeInterval(-configuration.confirmationDuration)
    let window =
      samples
      .filter {
        $0.externalPower
          && $0.timestamp >= windowStart
          && $0.batteryPowerWatts?.isFinite == true
      }
      .sorted { $0.timestamp < $1.timestamp }

    guard window.count >= configuration.minimumSamples else {
      let confidence = min(0.49, Double(window.count) / Double(configuration.minimumSamples) * 0.49)
      return assessment(
        .unknown,
        confidence,
        sample,
        nil,
        L10n.string("Collecting enough battery-power samples")
      )
    }

    guard let firstTimestamp = window.first?.timestamp,
      let lastTimestamp = window.last?.timestamp
    else {
      return assessment(
        .unknown,
        0,
        sample,
        nil,
        L10n.string("Battery power direction is unavailable"))
    }

    let observedDuration = lastTimestamp.timeIntervalSince(firstTimestamp)
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
        L10n.string("Waiting for the confirmation window to complete")
      )
    }

    let powers = window.compactMap(\.batteryPowerWatts).sorted()
    guard let medianPower = median(powers), medianPower.isFinite else {
      return assessment(
        .unknown,
        0,
        sample,
        nil,
        L10n.string("Battery power direction is unavailable"))
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
    if let percent = sample.batteryPercent,
      !percent.isFinite || !(0...100).contains(percent)
    {
      return L10n.string("Battery percentage is outside the valid range")
    }
    if let power = sample.batteryPowerWatts,
      !power.isFinite || abs(power) > configuration.maximumPlausibleBatteryPowerWatts
    {
      return L10n.string("Battery power is outside the plausible range")
    }
    if let measured = sample.adapterMeasuredPowerWatts,
      !measured.isFinite
        || measured < 0
        || measured > configuration.maximumPlausibleAdapterPowerWatts
    {
      return L10n.string("Measured adapter power is invalid")
    }
    if let rated = sample.adapterRatedPowerWatts,
      !rated.isFinite
        || rated <= 0
        || rated > configuration.maximumPlausibleAdapterPowerWatts
    {
      return L10n.string("Rated adapter power is invalid")
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
    if let batteryPercent, batteryPercent.isFinite, batteryPercent >= 99.5 {
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
      let derived = measured - battery
      systemPower = derived.isFinite ? max(0, derived) : nil
    } else {
      systemPower = nil
    }

    let alignmentNote = timestampsAligned
      ? ""
      : " " + L10n.string(
        "Adapter and battery samples were not aligned, so system power was not estimated.")

    return PowerAssessment(
      status: status,
      confidence: confidence.isFinite ? max(0, min(1, confidence)) : 0,
      batteryPowerWatts: medianBatteryPower?.isFinite == true ? medianBatteryPower : nil,
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
      return L10n.format(
        "Battery is continuously discharging while external power is connected (median %.1f W)",
        power)
    case .borderline:
      return L10n.string("Power is near the configured boundary")
    case .chargingBattery:
      return L10n.string("External power supports the system and charges the battery")
    case .powerAdapterOnly:
      return L10n.string("The Mac is on adapter power and the battery is effectively full")
    case .sufficient:
      return L10n.string("No sustained battery discharge is detected")
    default:
      return L10n.string("Power state cannot be determined")
    }
  }
}