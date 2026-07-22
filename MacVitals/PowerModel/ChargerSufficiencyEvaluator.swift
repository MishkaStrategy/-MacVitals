import Foundation

nonisolated struct PowerSample: Sendable, Equatable {
    let timestamp: Date
    let externalPower: Bool
    let batteryPowerWatts: Double?
    let adapterRatedPowerWatts: Double?
    let adapterMeasuredPowerWatts: Double?
    let batteryPercent: Double?
}

nonisolated struct ChargerSufficiencyConfiguration: Sendable, Equatable {
    var insufficientDischargeWatts: Double = 2.0
    var borderlineDischargeWatts: Double = 0.5
    var confirmationDuration: TimeInterval = 20
    var minimumSamples: Int = 5
    var maximumTimestampSkew: TimeInterval = 5
}

nonisolated struct ChargerSufficiencyEvaluator: Sendable {
    private(set) var samples: [PowerSample] = []
    private(set) var lastStableStatus: PowerSufficiencyStatus = .unknown
    let configuration: ChargerSufficiencyConfiguration

    init(configuration: ChargerSufficiencyConfiguration = .init()) { self.configuration = configuration }

    mutating func reset() { samples.removeAll(keepingCapacity: true); lastStableStatus = .unknown }

    mutating func evaluate(_ sample: PowerSample) -> PowerAssessment {
        samples.append(sample)
        let cutoff = sample.timestamp.addingTimeInterval(-max(60, configuration.confirmationDuration * 3))
        samples.removeAll { $0.timestamp < cutoff }
        guard sample.externalPower else {
            lastStableStatus = .notConnected
            return assessment(.notConnected, 1, sample, nil, "External power is not connected")
        }
        let windowStart = sample.timestamp.addingTimeInterval(-configuration.confirmationDuration)
        let window = samples.filter { $0.timestamp >= windowStart && $0.externalPower }
        let powers = window.compactMap(\.batteryPowerWatts).sorted()
        guard powers.count >= configuration.minimumSamples else {
            return assessment(.unknown, Double(powers.count) / Double(configuration.minimumSamples), sample, nil, "Collecting a stable power window")
        }
        guard let median = median(powers) else {
            return assessment(.unknown, 0, sample, nil, "Battery power direction is unavailable")
        }
        let conflict = sample.batteryPercent == 100 && median > configuration.insufficientDischargeWatts
        if conflict {
            lastStableStatus = .sensorConflict
            return assessment(.sensorConflict, 0.25, sample, median, "Battery state and power direction conflict")
        }
        let status: PowerSufficiencyStatus
        if median <= -configuration.insufficientDischargeWatts { status = .insufficient }
        else if median < -configuration.borderlineDischargeWatts { status = .borderline }
        else if median > configuration.borderlineDischargeWatts { status = .chargingBattery }
        else { status = .sufficient }
        lastStableStatus = status
        let confidence = min(1, Double(powers.count) / Double(max(configuration.minimumSamples, 10)))
        return assessment(status, confidence, sample, median, explanation(status, median))
    }

    private func assessment(_ status: PowerSufficiencyStatus, _ confidence: Double,
                            _ sample: PowerSample, _ medianBatteryPower: Double?, _ explanation: String) -> PowerAssessment {
        let systemPower: Double?
        if let measured = sample.adapterMeasuredPowerWatts, let battery = medianBatteryPower {
            systemPower = max(0, measured - battery)
        } else { systemPower = nil }
        let balance = sample.adapterMeasuredPowerWatts.flatMap { measured in systemPower.map { measured - $0 } }
        return PowerAssessment(status: status, confidence: confidence,
                               batteryPowerWatts: medianBatteryPower,
                               estimatedSystemPowerWatts: systemPower,
                               powerBalanceWatts: balance,
                               explanation: explanation)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[mid - 1] + values[mid]) / 2 : values[mid]
    }

    private func explanation(_ status: PowerSufficiencyStatus, _ power: Double) -> String {
        switch status {
        case .insufficient: return "Battery is continuously discharging while external power is connected (median \(String(format: "%.1f", power)) W)"
        case .borderline: return "Power is near the configured boundary"
        case .chargingBattery: return "External power supports the system and charges the battery"
        case .sufficient: return "No sustained battery discharge is detected"
        default: return "Power state cannot be determined"
        }
    }
}
