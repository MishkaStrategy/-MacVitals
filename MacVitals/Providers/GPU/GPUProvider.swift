import Foundation
import Metal

protocol GPUProviding: Sendable { func sample() -> MetricValue<GPUStats> }

struct CapabilityGPUProvider: GPUProviding {
    func sample() -> MetricValue<GPUStats> {
        let device = MTLCreateSystemDefaultDevice()
        let value = GPUStats(name: device?.name,
                             metalAvailable: device != nil,
                             recommendedWorkingSetBytes: device.map { UInt64($0.recommendedMaxWorkingSetSize) },
                             systemUtilizationPercent: nil,
                             utilizationAvailability: .unsupported)
        return MetricValue(value: value, unit: .percent, availability: .available,
                           quality: .direct, source: .metal, timestamp: Date(),
                           isEstimated: false,
                           message: "System GPU utilization is unavailable through a universal public API")
    }
}
