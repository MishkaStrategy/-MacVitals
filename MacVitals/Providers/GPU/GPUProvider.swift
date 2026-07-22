import Foundation
import Metal

protocol GPUProviding: Sendable {
  func sample() -> MetricValue<GPUStats>
}

nonisolated enum GPUCapabilityMapper {
  static func makeStats(
    name: String,
    registryID: UInt64,
    hasUnifiedMemory: Bool,
    isLowPower: Bool,
    isRemovable: Bool,
    recommendedWorkingSetBytes: UInt64
  ) -> GPUStats {
    GPUStats(
      name: name,
      metalAvailable: true,
      registryID: registryID,
      hasUnifiedMemory: hasUnifiedMemory,
      isLowPower: isLowPower,
      isRemovable: isRemovable,
      recommendedWorkingSetBytes: recommendedWorkingSetBytes,
      systemUtilizationPercent: nil,
      utilizationAvailability: .unsupported)
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

    let value = GPUCapabilityMapper.makeStats(
      name: device.name,
      registryID: device.registryID,
      hasUnifiedMemory: device.hasUnifiedMemory,
      isLowPower: device.isLowPower,
      isRemovable: device.isRemovable,
      recommendedWorkingSetBytes: UInt64(device.recommendedMaxWorkingSetSize))

    return MetricValue(
      value: value,
      unit: .percent,
      availability: .available,
      quality: .direct,
      source: .metal,
      timestamp: Date(),
      isEstimated: false,
      message: "Metal device capabilities are available; system-wide GPU utilization is not exposed by a universal public API")
  }
}
