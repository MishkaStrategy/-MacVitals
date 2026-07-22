import Darwin
import Darwin.Mach
import Foundation

nonisolated enum MemoryMath {
  static func usedBytes(active: UInt64, wired: UInt64, compressed: UInt64) -> UInt64 {
    saturatingAdd(active, wired, compressed)
  }

  static func availableBytes(physical: UInt64, used: UInt64) -> UInt64 {
    physical >= used ? physical - used : 0
  }

  static func percent(used: UInt64, physical: UInt64) -> Double {
    guard physical > 0 else { return 0 }
    return min(100, max(0, Double(used) / Double(physical) * 100))
  }

  static func bytes(pages: UInt64, pageSize: UInt64) -> UInt64 {
    pages.multipliedReportingOverflow(by: pageSize).overflow
      ? UInt64.max
      : pages * pageSize
  }

  private static func saturatingAdd(_ values: UInt64...) -> UInt64 {
    values.reduce(0) { partial, value in
      let result = partial.addingReportingOverflow(value)
      return result.overflow ? UInt64.max : result.partialValue
    }
  }
}

private nonisolated struct SwapSnapshot: Sendable, Equatable {
  let totalBytes: UInt64
  let usedBytes: UInt64
  let freeBytes: UInt64
}

struct MemoryProvider: Sendable {
  func sample() -> MetricValue<MemoryStats> {
    let timestamp = Date()
    var stats = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else {
      return .unavailable(
        unit: .bytes, availability: .providerError,
        source: .machHostStatistics, message: "host_statistics64 failed: \(result)")
    }

    var pageSize: vm_size_t = 0
    let pageSizeResult = host_page_size(mach_host_self(), &pageSize)
    guard pageSizeResult == KERN_SUCCESS, pageSize > 0 else {
      return .unavailable(
        unit: .bytes, availability: .providerError,
        source: .machHostStatistics, message: "host_page_size failed: \(pageSizeResult)")
    }

    let page = UInt64(pageSize)
    let physical = ProcessInfo.processInfo.physicalMemory
    let active = MemoryMath.bytes(pages: UInt64(stats.active_count), pageSize: page)
    let inactive = MemoryMath.bytes(pages: UInt64(stats.inactive_count), pageSize: page)
    let wired = MemoryMath.bytes(pages: UInt64(stats.wire_count), pageSize: page)
    let compressed = MemoryMath.bytes(pages: UInt64(stats.compressor_page_count), pageSize: page)
    let free = MemoryMath.bytes(pages: UInt64(stats.free_count), pageSize: page)
    let purgeable = MemoryMath.bytes(pages: UInt64(stats.purgeable_count), pageSize: page)
    let speculative = MemoryMath.bytes(pages: UInt64(stats.speculative_count), pageSize: page)
    let calculatedUsed = MemoryMath.usedBytes(
      active: active, wired: wired, compressed: compressed)
    let used = min(physical, calculatedUsed)
    let available = MemoryMath.availableBytes(physical: physical, used: used)
    let swap = readSwapSnapshot()

    let value = MemoryStats(
      physicalBytes: physical,
      usedBytes: used,
      freeBytes: free,
      availableBytes: available,
      activeBytes: active,
      inactiveBytes: inactive,
      wiredBytes: wired,
      compressedBytes: compressed,
      purgeableBytes: purgeable,
      speculativeBytes: speculative,
      swapTotalBytes: swap?.totalBytes,
      swapUsedBytes: swap?.usedBytes,
      swapFreeBytes: swap?.freeBytes,
      pressure: nil,
      usedPercent: MemoryMath.percent(used: used, physical: physical))

    return MetricValue(
      value: value,
      unit: .bytes,
      availability: .available,
      quality: .derived,
      source: .machHostStatistics,
      timestamp: timestamp,
      isEstimated: false,
      message: telemetryMessage(swapAvailable: swap != nil))
  }

  private func readSwapSnapshot() -> SwapSnapshot? {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    let result = withUnsafeMutablePointer(to: &usage) { pointer in
      sysctlbyname("vm.swapusage", pointer, &size, nil, 0)
    }
    guard result == 0, size == MemoryLayout<xsw_usage>.size else { return nil }
    return SwapSnapshot(
      totalBytes: usage.xsu_total,
      usedBytes: usage.xsu_used,
      freeBytes: usage.xsu_avail)
  }

  private func telemetryMessage(swapAvailable: Bool) -> String {
    let swapStatus = swapAvailable ? "swap available" : "swap unavailable"
    return "Used memory is active + wired + compressed; \(swapStatus); memory pressure is not inferred from usage percentage"
  }
}
