import Foundation
import IOKit.ps

struct AdapterProvider: Sendable {
    func sample() -> MetricValue<AdapterStats> {
        let now = Date()
        guard let unmanaged = IOPSCopyExternalPowerAdapterDetails(),
              let details = unmanaged.takeRetainedValue() as? [String: Any] else {
            let value = AdapterStats(connected: false, manufacturer: nil, model: nil,
                                     transport: nil, ratedPowerWatts: nil, voltageVolts: nil,
                                     currentAmperes: nil, measuredPowerWatts: nil)
            return MetricValue(value: value, unit: .watts, availability: .temporarilyUnavailable,
                               quality: .direct, source: .iokitPowerSources,
                               timestamp: now, isEstimated: false, message: "No external adapter details")
        }
        func number(_ keys: [String]) -> Double? {
            for key in keys { if let number = details[key] as? NSNumber { return number.doubleValue } }
            return nil
        }
        let watts = number(["Watts", "AdapterWatts"])
        let voltageMV = number(["AdapterVoltage", "Voltage"])
        let currentMA = number(["Current", "AdapterCurrent"])
        let voltage = voltageMV.map { $0 > 100 ? $0 / 1000 : $0 }
        let current = currentMA.map { abs($0) > 100 ? $0 / 1000 : $0 }
        let value = AdapterStats(connected: true,
                                 manufacturer: details["Manufacturer"] as? String,
                                 model: details["Name"] as? String ?? details["Model"] as? String,
                                 transport: details["Description"] as? String,
                                 ratedPowerWatts: watts, voltageVolts: voltage,
                                 currentAmperes: current, measuredPowerWatts: nil)
        return MetricValue(value: value, unit: .watts, availability: .available,
                           quality: .direct, source: .iokitPowerSources,
                           timestamp: now, isEstimated: false,
                           message: "Rated/negotiated adapter data; measured input power is not claimed")
    }
}
