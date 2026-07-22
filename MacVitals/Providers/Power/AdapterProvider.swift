import Foundation
import IOKit.ps

struct AdapterProvider: Sendable {
  func sample() -> MetricValue<AdapterStats> {
    let now = Date()
    guard let unmanaged = IOPSCopyExternalPowerAdapterDetails(),
      let details = unmanaged.takeRetainedValue() as? [String: Any]
    else {
      return unavailableAdapter(timestamp: now)
    }

    let rawWatts = AdapterValueNormalizer.firstFiniteNumber(
      keys: ["Watts", "AdapterWatts"],
      in: details)
    let rawVoltage = AdapterValueNormalizer.firstFiniteNumber(
      keys: ["AdapterVoltage", "Voltage"],
      in: details)
    let rawCurrent = AdapterValueNormalizer.firstFiniteNumber(
      keys: ["Current", "AdapterCurrent"],
      in: details)
    let value = AdapterStats(
      connected: true,
      manufacturer: AdapterValueNormalizer.text(details["Manufacturer"]),
      model: AdapterValueNormalizer.text(details["Name"])
        ?? AdapterValueNormalizer.text(details["Model"]),
      transport: AdapterValueNormalizer.text(details["Description"]),
      ratedPowerWatts: AdapterValueNormalizer.ratedPowerWatts(rawWatts),
      voltageVolts: AdapterValueNormalizer.voltageVolts(rawVoltage),
      currentAmperes: AdapterValueNormalizer.currentAmperes(rawCurrent),
      measuredPowerWatts: nil)

    return MetricValue(
      value: value,
      unit: .watts,
      availability: .available,
      quality: .direct,
      source: .iokitPowerSources,
      timestamp: now,
      isEstimated: false,
      message: "Validated rated/negotiated adapter data; measured input power is not claimed")
  }

  private func unavailableAdapter(timestamp: Date) -> MetricValue<AdapterStats> {
    let value = AdapterStats(
      connected: false,
      manufacturer: nil,
      model: nil,
      transport: nil,
      ratedPowerWatts: nil,
      voltageVolts: nil,
      currentAmperes: nil,
      measuredPowerWatts: nil)
    return MetricValue(
      value: value,
      unit: .watts,
      availability: .temporarilyUnavailable,
      quality: .direct,
      source: .iokitPowerSources,
      timestamp: timestamp,
      isEstimated: false,
      message: "No external adapter details")
  }
}
