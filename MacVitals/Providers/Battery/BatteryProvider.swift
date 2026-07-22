import Foundation
import IOKit
import IOKit.ps

struct BatteryProvider: Sendable {
    func sample() -> MetricValue<BatteryStats> {
        let now = Date()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
            let absent = BatteryStats(present: false, percentage: nil, state: .absent,
                                      externalPowerConnected: false, timeRemainingMinutes: nil,
                                      timeToFullMinutes: nil, cycleCount: nil, condition: nil,
                                      currentCapacityMah: nil, maxCapacityMah: nil, designCapacityMah: nil,
                                      healthPercent: nil, temperatureCelsius: nil, voltageVolts: nil,
                                      currentAmperes: nil, batteryPowerWatts: nil)
            return MetricValue(value: absent, unit: .percent, availability: .unsupported,
                               quality: .direct, source: .iokitPowerSources, timestamp: now,
                               isEstimated: false, message: "No internal battery")
        }
        let current = number(description[kIOPSCurrentCapacityKey])
        let maximum = number(description[kIOPSMaxCapacityKey])
        let percentage = maximum.flatMap { $0 > 0 ? min(100, max(0, (current ?? 0) / $0 * 100)) : nil }
        let external = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        let state: BatteryState = charging ? .charging : (external ? .adapterPower : .discharging)
        let registry = readSmartBatteryRegistry()
        let voltage = millivoltsToVolts(number(registry["Voltage"]))
        let currentA = milliampsToAmps(number(registry["Amperage"] ?? registry["InstantAmperage"]))
        let power = alignedPower(voltage: voltage, current: currentA)
        let design = number(registry["DesignCapacity"])
        let maxMah = number(registry["AppleRawMaxCapacity"] ?? registry["MaxCapacity"])
        let currentMah = number(registry["AppleRawCurrentCapacity"] ?? registry["CurrentCapacity"])
        let health = (maxMah != nil && design != nil && design! > 0) ? min(100, max(0, maxMah! / design! * 100)) : nil
        let temperature = number(registry["Temperature"]).map { $0 > 100 ? $0 / 100.0 : $0 }
        let minutes = (description[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue
        let fullMinutes = (description[kIOPSTimeToFullChargeKey] as? NSNumber)?.intValue
        let value = BatteryStats(present: true, percentage: percentage, state: state,
                                 externalPowerConnected: external,
                                 timeRemainingMinutes: validMinutes(minutes),
                                 timeToFullMinutes: validMinutes(fullMinutes),
                                 cycleCount: (registry["CycleCount"] as? NSNumber)?.intValue,
                                 condition: description[kIOPSBatteryHealthKey] as? String,
                                 currentCapacityMah: currentMah, maxCapacityMah: maxMah,
                                 designCapacityMah: design, healthPercent: health,
                                 temperatureCelsius: temperature, voltageVolts: voltage,
                                 currentAmperes: currentA, batteryPowerWatts: power)
        return MetricValue(value: value, unit: .percent, availability: .available,
                           quality: registry.isEmpty ? .direct : .experimental,
                           source: registry.isEmpty ? .iokitPowerSources : .iokitRegistry,
                           timestamp: now, isEstimated: false,
                           message: registry.isEmpty ? nil : "Extended fields are capability-checked IORegistry values")
    }

    private func readSmartBatteryRegistry() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return [:] }
        return dictionary
    }

    private func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
    private func millivoltsToVolts(_ value: Double?) -> Double? { value.map { $0 / 1000.0 }.flatMap { (0...30).contains($0) ? $0 : nil } }
    private func milliampsToAmps(_ value: Double?) -> Double? { value.map { $0 / 1000.0 }.flatMap { (-30...30).contains($0) ? $0 : nil } }
    private func alignedPower(voltage: Double?, current: Double?) -> Double? {
        guard let voltage, let current else { return nil }
        return voltage * current
    }
    private func validMinutes(_ value: Int?) -> Int? { guard let value, value >= 0, value < 100_000 else { return nil }; return value }
}
