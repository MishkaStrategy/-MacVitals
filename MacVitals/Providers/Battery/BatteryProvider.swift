import Foundation
import IOKit
import IOKit.ps

struct BatteryProvider: Sendable {
  func sample() -> MetricValue<BatteryStats> {
    let now = Date()
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
      let description = internalBatteryDescription(info: info, sources: sources)
    else {
      return absentBattery(timestamp: now)
    }

    let current = BatteryValueNormalizer.finiteNumber(description[kIOPSCurrentCapacityKey])
    let maximum = BatteryValueNormalizer.finiteNumber(description[kIOPSMaxCapacityKey])
    let percentage = BatteryValueNormalizer.percentage(current: current, maximum: maximum)
    let external = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
    let charging = description[kIOPSIsChargingKey] as? Bool ?? false
    let state = BatteryValueNormalizer.state(
      charging: charging,
      externalPower: external,
      percentage: percentage)

    let registry = readSmartBatteryRegistry()
    let voltage = BatteryValueNormalizer.millivoltsToVolts(
      BatteryValueNormalizer.finiteNumber(registry["Voltage"]))
    let currentAmperes = BatteryValueNormalizer.milliampsToAmps(
      BatteryValueNormalizer.finiteNumber(
        registry["Amperage"] ?? registry["InstantAmperage"]))
    let batteryPower = BatteryValueNormalizer.powerWatts(
      voltage: voltage,
      current: currentAmperes)
    let designCapacity = BatteryValueNormalizer.capacityMah(
      BatteryValueNormalizer.finiteNumber(registry["DesignCapacity"]))
    let maximumCapacity = BatteryValueNormalizer.capacityMah(
      BatteryValueNormalizer.finiteNumber(
        registry["AppleRawMaxCapacity"] ?? registry["MaxCapacity"]))
    let currentCapacity = BatteryValueNormalizer.capacityMah(
      BatteryValueNormalizer.finiteNumber(
        registry["AppleRawCurrentCapacity"] ?? registry["CurrentCapacity"]))
    let health = BatteryValueNormalizer.healthPercent(
      maximumMah: maximumCapacity,
      designMah: designCapacity)
    let temperature = BatteryValueNormalizer.temperatureCelsius(
      raw: BatteryValueNormalizer.finiteNumber(registry["Temperature"]))
    let cycleCount = BatteryValueNormalizer.cycleCount(registry["CycleCount"])
    let minutes = (description[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue
    let fullMinutes = (description[kIOPSTimeToFullChargeKey] as? NSNumber)?.intValue
    let condition = BatteryValueNormalizer.text(description[kIOPSBatteryHealthKey])
    let hasExtendedValues = [
      voltage,
      currentAmperes,
      batteryPower,
      designCapacity,
      maximumCapacity,
      currentCapacity,
      health,
      temperature,
      cycleCount.map(Double.init),
    ].contains { $0 != nil }

    let value = BatteryStats(
      present: true,
      percentage: percentage,
      state: state,
      externalPowerConnected: external,
      timeRemainingMinutes: BatteryValueNormalizer.validMinutes(minutes),
      timeToFullMinutes: BatteryValueNormalizer.validMinutes(fullMinutes),
      cycleCount: cycleCount,
      condition: condition,
      currentCapacityMah: currentCapacity,
      maxCapacityMah: maximumCapacity,
      designCapacityMah: designCapacity,
      healthPercent: health,
      temperatureCelsius: temperature,
      voltageVolts: voltage,
      currentAmperes: currentAmperes,
      batteryPowerWatts: batteryPower)

    return MetricValue(
      value: value,
      unit: .percent,
      availability: .available,
      quality: hasExtendedValues ? .experimental : .direct,
      source: hasExtendedValues ? .iokitRegistry : .iokitPowerSources,
      timestamp: now,
      isEstimated: false,
      message: hasExtendedValues
        ? "Extended fields are validated, capability-checked IORegistry values"
        : nil)
  }

  private func internalBatteryDescription(
    info: CFTypeRef,
    sources: [CFTypeRef]
  ) -> [String: Any]? {
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any]
      else { continue }
      if (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType {
        return description
      }
    }
    return nil
  }

  private func absentBattery(timestamp: Date) -> MetricValue<BatteryStats> {
    let value = BatteryStats(
      present: false,
      percentage: nil,
      state: .absent,
      externalPowerConnected: false,
      timeRemainingMinutes: nil,
      timeToFullMinutes: nil,
      cycleCount: nil,
      condition: nil,
      currentCapacityMah: nil,
      maxCapacityMah: nil,
      designCapacityMah: nil,
      healthPercent: nil,
      temperatureCelsius: nil,
      voltageVolts: nil,
      currentAmperes: nil,
      batteryPowerWatts: nil)
    return MetricValue(
      value: value,
      unit: .percent,
      availability: .unsupported,
      quality: .direct,
      source: .iokitPowerSources,
      timestamp: timestamp,
      isEstimated: false,
      message: "No internal battery")
  }

  private func readSmartBatteryRegistry() -> [String: Any] {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault,
      IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return [:] }
    defer { IOObjectRelease(service) }

    var properties: Unmanaged<CFMutableDictionary>?
    guard
      IORegistryEntryCreateCFProperties(
        service,
        &properties,
        kCFAllocatorDefault,
        0) == KERN_SUCCESS,
      let dictionary = properties?.takeRetainedValue() as? [String: Any]
    else { return [:] }
    return dictionary
  }
}
