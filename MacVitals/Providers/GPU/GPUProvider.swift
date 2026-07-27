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
  func read() -> Double? {
    for className in ["IOAccelerator", "AGXAccelerator"] {
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

    var dictionaries: [[String: Any]] = []
    var service = IOIteratorNext(iterator)
    while service != 0 {
      let currentService = service
      if let unmanaged = IORegistryEntryCreateCFProperty(
        currentService,
        "PerformanceStatistics" as CFString,
        kCFAllocatorDefault,
        0),
        let dictionary = unmanaged.takeRetainedValue() as? [String: Any]
      {
        dictionaries.append(dictionary)
      }
      IOObjectRelease(currentService)
      service = IOIteratorNext(iterator)
    }
    return GPUUtilizationNormalizer.percentage(from: dictionaries)
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

struct CapabilityGPUProvider: GPUProviding {
  func sample() -> MetricValue<GPUStats> {
    guard let device = MTLCreateSystemDefaultDevice() else {
      return .unavailable(
        unit: .percent,
        availability: .unsupported,
        source: .metal,
        message: "No Metal-compatible default GPU was reported by macOS")
    }

    let utilization = IORegistryGPUUtilizationReader().read()
    let value = GPUCapabilityMapper.makeStats(
      name: device.name,
      registryID: device.registryID,
      hasUnifiedMemory: device.hasUnifiedMemory,
      isLowPower: device.isLowPower,
      isRemovable: device.isRemovable,
      recommendedWorkingSetBytes: UInt64(device.recommendedMaxWorkingSetSize),
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
