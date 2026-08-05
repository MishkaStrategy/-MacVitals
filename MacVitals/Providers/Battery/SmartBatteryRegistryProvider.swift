import Foundation
import IOKit

nonisolated struct SmartBatteryRegistrySnapshot: Sendable, Equatable {
  let voltageMillivolts: Double?
  let amperageMilliamps: Double?
  let designCapacityMah: Double?
  let maximumCapacityMah: Double?
  let currentCapacityMah: Double?
  let temperatureRaw: Double?
  let cycleCount: Int?
  let systemLoadMilliwatts: Double?
  let systemInputMilliwatts: Double?

  static let empty = SmartBatteryRegistrySnapshot(
    voltageMillivolts: nil,
    amperageMilliamps: nil,
    designCapacityMah: nil,
    maximumCapacityMah: nil,
    currentCapacityMah: nil,
    temperatureRaw: nil,
    cycleCount: nil,
    systemLoadMilliwatts: nil,
    systemInputMilliwatts: nil)
}

nonisolated enum SmartBatteryRegistryDecoder {
  static func decode(_ properties: [String: Any]) -> SmartBatteryRegistrySnapshot {
    let telemetry = properties["PowerTelemetryData"] as? [String: Any]
    return SmartBatteryRegistrySnapshot(
      voltageMillivolts: BatteryValueNormalizer.finiteNumber(properties["Voltage"]),
      amperageMilliamps: BatteryValueNormalizer.finiteNumber(
        properties["Amperage"] ?? properties["InstantAmperage"]),
      designCapacityMah: BatteryValueNormalizer.finiteNumber(properties["DesignCapacity"]),
      maximumCapacityMah: BatteryValueNormalizer.finiteNumber(
        properties["AppleRawMaxCapacity"] ?? properties["MaxCapacity"]),
      currentCapacityMah: BatteryValueNormalizer.finiteNumber(
        properties["AppleRawCurrentCapacity"] ?? properties["CurrentCapacity"]),
      temperatureRaw: BatteryValueNormalizer.finiteNumber(properties["Temperature"]),
      cycleCount: BatteryValueNormalizer.cycleCount(properties["CycleCount"]),
      systemLoadMilliwatts: BatteryValueNormalizer.finiteNumber(telemetry?["SystemLoad"]),
      systemInputMilliwatts: BatteryValueNormalizer.finiteNumber(
        telemetry?["SystemPowerIn"]))
  }
}

struct SmartBatteryRegistryProvider: Sendable {
  func sample() -> SmartBatteryRegistrySnapshot? {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault,
      IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }

    var properties: Unmanaged<CFMutableDictionary>?
    guard
      IORegistryEntryCreateCFProperties(
        service,
        &properties,
        kCFAllocatorDefault,
        0) == KERN_SUCCESS,
      let dictionary = properties?.takeRetainedValue() as? [String: Any]
    else { return nil }
    return SmartBatteryRegistryDecoder.decode(dictionary)
  }
}
