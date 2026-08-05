import Foundation
import IOKit
import Metal

protocol GPUProviding: Sendable {
  func sample() -> MetricValue<GPUStats>
}

nonisolated enum GPUUtilizationNormalizer {
  static let knownKeys = [
    "Device Utilization %",
    "GPU Utilization %",
    "GPU Activity(%)",
    "Renderer Utilization %",
  ]

  static func percentage(from dictionaries: [[String: Any]]) -> Double? {
    dictionaries.compactMap(percentage(from:)).max()
  }

  static func percentage(from dictionary: [String: Any]) -> Double? {
    for key in knownKeys {
      guard let value = finiteNumber(dictionary[key]) else { continue }
      guard (0...100).contains(value) else { continue }
      return value
    }
    return nil
  }

  private static func finiteNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return nil }
    let result = number.doubleValue
    return result.isFinite ? result : nil
  }
}

struct IORegistryGPUUtilizationReader: Sendable {
  private static let acceleratorClassNames = ["IOAccelerator", "AGXAccelerator"]

  func read() -> Double? {
    for className in Self.acceleratorClassNames {
      if let value = read(className: className) { return value }
    }
    return nil
  }

  private func read(className: String) -> Double? {
    guard let matching = IOServiceMatching(className) else { return nil }
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(iterator) }

    var maximum: Double?
    var service = IOIteratorNext(iterator)
    while service != 0 {
      let currentService = service
      if let unmanaged = IORegistryEntryCreateCFProperty(
        currentService,
        "PerformanceStatistics" as CFString,
        kCFAllocatorDefault,
        0),
        let dictionary = unmanaged.takeRetainedValue() as? [String: Any],
        let value = GPUUtilizationNormalizer.percentage(from: dictionary)
      {
        maximum = maximum.map { max($0, value) } ?? value
      }
      IOObjectRelease(currentService)
      service = IOIteratorNext(iterator)
    }
    return maximum
  }
}

nonisolated enum GPUCapabilityMapper {
  static func makeStats(
    name: String,
    registryID: UInt64,
    hasUnifiedMemory: Bool,
    isLowPower: Bool,
    isRemovable: Bool,
    recommendedWorkingSetBytes: UInt64,
    systemUtilizationPercent: Double? = nil
  ) -> GPUStats {
    GPUStats(
      name: name,
      metalAvailable: true,
      registryID: registryID,
      hasUnifiedMemory: hasUnifiedMemory,
      isLowPower: isLowPower,
      isRemovable: isRemovable,
      recommendedWorkingSetBytes: recommendedWorkingSetBytes,
      systemUtilizationPercent: systemUtilizationPercent,
      utilizationAvailability: systemUtilizationPercent == nil
        ? .temporarilyUnavailable
        : .available)
  }
}

private struct GPUStaticCapability: Sendable {
  let name: String
  let registryID: UInt64
  let hasUnifiedMemory: Bool
  let isLowPower: Bool
  let isRemovable: Bool
  let recommendedWorkingSetBytes: UInt64

  init?(device: any MTLDevice) {
    name = device.name
    registryID = device.registryID
    hasUnifiedMemory = device.hasUnifiedMemory
    isLowPower = device.isLowPower
    isRemovable = device.isRemovable
    recommendedWorkingSetBytes = UInt64(device.recommendedMaxWorkingSetSize)
  }
}

struct CapabilityGPUProvider: GPUProviding {
  private let capability: GPUStaticCapability?

  init() {
    capability = MTLCreateSystemDefaultDevice().flatMap(GPUStaticCapability.init(device:))
  }

  func sample() -> MetricValue<GPUStats> {
    guard let capability else {
      return .unavailable(
        unit: .percent,
        availability: .unsupported,
        source: .metal,
        message: "No Metal-compatible default GPU was reported by macOS")
    }

    let utilization = IORegistryGPUUtilizationReader().read()
    let value = GPUCapabilityMapper.makeStats(
      name: capability.name,
      registryID: capability.registryID,
      hasUnifiedMemory: capability.hasUnifiedMemory,
      isLowPower: capability.isLowPower,
      isRemovable: capability.isRemovable,
      recommendedWorkingSetBytes: capability.recommendedWorkingSetBytes,
      systemUtilizationPercent: utilization)

    return MetricValue(
      value: value,
      unit: .percent,
      availability: .available,
      quality: utilization == nil ? .direct : .experimental,
      source: utilization == nil ? .metal : .iokitRegistry,
      timestamp: Date(),
      isEstimated: false,
      message: utilization == nil
        ? "GPU capabilities are available; utilization is temporarily unavailable"
        : "GPU utilization was read from capability-checked IORegistry performance statistics")
  }
}
