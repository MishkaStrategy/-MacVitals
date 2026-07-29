import Foundation
import IOKit.ps

struct AdapterProvider: Sendable {
  func sample() -> MetricValue<AdapterStats> {
    let now = Date()
    guard let unmanaged = IOPSCopyExternalPowerAdapterDetails(),
      let details = unmanaged.takeRetainedValue() as? [String: Any]
    else {
      return .unavailable(
        unit: .watts,
        availability: .temporarilyUnavailable,
        source: .iokitPowerSources,
        message: "External adapter details are unavailable or no adapter is attached")
    }

    let rawWatts = AdapterValueNormalizer.finiteNumber(
      details[kIOPSPowerAdapterWattsKey])
    let rawCurrentMilliamps = AdapterValueNormalizer.finiteNumber(
      details[kIOPSPowerAdapterCurrentKey])
    let value = AdapterStats(
      connected: true,
      manufacturer: nil,
      model: nil,
      transport: nil,
      ratedPowerWatts: AdapterValueNormalizer.ratedPowerWatts(rawWatts),
      voltageVolts: nil,
      currentAmperes: AdapterValueNormalizer.milliampsToAmps(rawCurrentMilliamps),
      measuredPowerWatts: nil)

    return MetricValue(
      value: value,
      unit: .watts,
      availability: .available,
      quality: .direct,
      source: .iokitPowerSources,
      timestamp: now,
      isEstimated: false,
      message:
        "Validated public adapter rated-power and current fields; measured input power is not claimed"
    )
  }
}
