import Darwin.Mach
import Foundation

nonisolated enum MemoryMath {
    static func usedBytes(active: UInt64, inactive: UInt64, wired: UInt64, compressed: UInt64) -> UInt64 {
        active.addingReportingOverflow(wired).partialValue
            .addingReportingOverflow(compressed).partialValue
    }

    static func percent(used: UInt64, physical: UInt64) -> Double {
        guard physical > 0 else { return 0 }
        return min(100, max(0, Double(used) / Double(physical) * 100))
    }
}

struct MemoryProvider: Sendable {
    func sample() -> MetricValue<MemoryStats> {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return .unavailable(unit: .bytes, availability: .providerError,
                                source: .machHostStatistics, message: "host_statistics64 failed")
        }
        let page = UInt64(vm_kernel_page_size)
        let physical = ProcessInfo.processInfo.physicalMemory
        let active = UInt64(stats.active_count) * page
        let inactive = UInt64(stats.inactive_count) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let free = UInt64(stats.free_count) * page
        let used = min(physical, MemoryMath.usedBytes(active: active, inactive: inactive, wired: wired, compressed: compressed))
        let pressure = MemoryMath.percent(used: used, physical: physical)
        let value = MemoryStats(physicalBytes: physical, usedBytes: used, freeBytes: free,
                                activeBytes: active, inactiveBytes: inactive, wiredBytes: wired,
                                compressedBytes: compressed, swapUsedBytes: 0,
                                pressure: pressure, usedPercent: pressure)
        return MetricValue(value: value, unit: .bytes, availability: .available,
                           quality: .derived, source: .machHostStatistics,
                           timestamp: Date(), isEstimated: false,
                           message: "Used = active + wired + compressed; differs from Activity Monitor")
    }
}
