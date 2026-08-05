import Darwin
import Foundation
import IOKit
import IOKit.ps

nonisolated enum BatterySourceResolution: Equatable, Sendable {
  case present
  case absent
  case providerError

  static func resolve(
    sourceCount: Int,
    classifiedSourceCount: Int,
    internalBatteryFound: Bool
  ) -> Self {
    guard sourceCount >= 0, classifiedSourceCount >= 0, classifiedSourceCount <= sourceCount else {
      return .providerError
    }
    if internalBatteryFound {
      return classifiedSourceCount > 0 ? .present : .providerError
    }
    if sourceCount == 0 { return .absent }
    return classifiedSourceCount == sourceCount ? .absent : .providerError
  }
}

nonisolated enum BatteryHardwareKind: Equatable, Sendable {
  case portable
  case desktop
  case unknown

  static func classify(modelIdentifier: String?) -> Self {
    guard let modelIdentifier else { return .unknown }
    let normalized = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return .unknown }
    if normalized.hasPrefix("MacBook") { return .portable }
    if normalized.hasPrefix("Macmini")
      || normalized.hasPrefix("MacStudio")
      || normalized.hasPrefix("MacPro")
      || normalized.hasPrefix("iMac")
    {
      return .desktop
    }
    return .unknown
  }
}

nonisolated struct BatteryAbsenceConfirmation: Equatable, Sendable {
  static let confirmationDuration: TimeInterval = 10
  static let minimumSamples = 3

  private(set) var firstObservedAt: Date?
  private(set) var sampleCount = 0

  mutating func reset() {
    firstObservedAt = nil
    sampleCount = 0
  }

  mutating func evaluate(
    timestamp: Date,
    absenceCandidate: Bool,
    smartBatteryServiceFound: Bool
  ) -> Bool {
    guard absenceCandidate, !smartBatteryServiceFound else {
      reset()
      return false
    }

    if let firstObservedAt, timestamp < firstObservedAt {
      reset()
    }
    if firstObservedAt == nil {
      firstObservedAt = timestamp
    }
    sampleCount += 1

    guard let firstObservedAt else { return false }
    return sampleCount >= Self.minimumSamples
      && timestamp.timeIntervalSince(firstObservedAt) >= Self.confirmationDuration
  }
}

nonisolated enum BatteryExternalPowerResolution: Equatable, Sendable {
  case connected
  case disconnected
  case unavailable

  static func resolve(
    rawState: String?,
    acPowerValue: String,
    batteryPowerValue: String
  ) -> Self {
    guard let rawState else { return .unavailable }
    if rawState == acPowerValue { return .connected }
    if rawState == batteryPowerValue { return .disconnected }
    return .unavailable
  }

  var isConnected: Bool? {
    switch self {
    case .connected: return true
    case .disconnected: return false
    case .unavailable: return nil
    }
  }
}

final class BatteryProvider: @unchecked Sendable {
  private let hardwareKind: BatteryHardwareKind
  private let absenceLock = NSLock()
  private var absenceConfirmation = BatteryAbsenceConfirmation()

  init() {
    hardwareKind = BatteryHardwareKind.classify(modelIdentifier: Self.readHardwareModel())
  }

  init(hardwareKind: BatteryHardwareKind) {
    self.hardwareKind = hardwareKind
  }

  func sample() -> MetricValue<BatteryStats> {
    let now = Date()
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
      resetAbsenceConfirmation()
      return unavailableBattery(
        timestamp: now,
        message: "IOPSCopyPowerSourcesInfo failed")
    }
    guard let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
      resetAbsenceConfirmation()
      return unavailableBattery(
        timestamp: now,
        message: "IOPSCopyPowerSourcesList failed")
    }

    let lookup = internalBatteryLookup(info: info, sources: sources)
    switch BatterySourceResolution.resolve(
      sourceCount: sources.count,
      classifiedSourceCount: lookup.classifiedSourceCount,
      internalBatteryFound: lookup.description != nil)
    {
    case .providerError:
      resetAbsenceConfirmation()
      return unavailableBattery(
        timestamp: now,
        message: "Power source descriptions or types were unavailable")
    case .absent:
      let smartBatteryFound = smartBatteryServiceExists()
      guard hardwareKind == .desktop else {
        resetAbsenceConfirmation()
        return unavailableBattery(
          timestamp: now,
          message: "No internal battery source was reported on a non-desktop or unknown Mac model")
      }
      guard confirmAbsence(timestamp: now, smartBatteryServiceFound: smartBatteryFound) else {
        return unavailableBattery(
          timestamp: now,
          message: smartBatteryFound
            ? "AppleSmartBattery exists while the power-source list reports no internal battery"
            : "Confirming that this desktop Mac has no internal battery")
      }
      return absentBattery(timestamp: now)
    case .present:
      resetAbsenceConfirmation()
    }

    guard let description = lookup.description else {
      resetAbsenceConfirmation()
      return unavailableBattery(
        timestamp: now,
        message: "Internal battery resolution was inconsistent")
    }

    let powerResolution = BatteryExternalPowerResolution.resolve(
      rawState: description[kIOPSPowerSourceStateKey] as? String,
      acPowerValue: kIOPSACPowerValue,
      batteryPowerValue: kIOPSBatteryPowerValue)
    guard let external = powerResolution.isConnected else {
      return unavailableBattery(
        timestamp: now,
        message: "Internal battery power-source state was unavailable or unrecognized")
    }

    let current = BatteryValueNormalizer.finiteNumber(description[kIOPSCurrentCapacityKey])
    let maximum = BatteryValueNormalizer.finiteNumber(description[kIOPSMaxCapacityKey])
    let percentage = BatteryValueNormalizer.percentage(current: current, maximum: maximum)
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

  private func internalBatteryLookup(
    info: CFTypeRef,
    sources: [CFTypeRef]
  ) -> (description: [String: Any]?, classifiedSourceCount: Int) {
    var classifiedSourceCount = 0
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any],
        let type = description[kIOPSTypeKey] as? String
      else { continue }
      classifiedSourceCount += 1
      if type == kIOPSInternalBatteryType {
        return (description, classifiedSourceCount)
      }
    }
    return (nil, classifiedSourceCount)
  }

  private func resetAbsenceConfirmation() {
    absenceLock.lock()
    absenceConfirmation.reset()
    absenceLock.unlock()
  }

  private func confirmAbsence(timestamp: Date, smartBatteryServiceFound: Bool) -> Bool {
    absenceLock.lock()
    defer { absenceLock.unlock() }
    return absenceConfirmation.evaluate(
      timestamp: timestamp,
      absenceCandidate: true,
      smartBatteryServiceFound: smartBatteryServiceFound)
  }

  private func unavailableBattery(
    timestamp: Date,
    message: String
  ) -> MetricValue<BatteryStats> {
    MetricValue(
      value: nil,
      unit: .percent,
      availability: .providerError,
      quality: .unknown,
      source: .iokitPowerSources,
      timestamp: timestamp,
      isEstimated: false,
      message: message)
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

  private func smartBatteryServiceExists() -> Bool {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault,
      IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return false }
    IOObjectRelease(service)
    return true
  }

  private func readSmartBatteryRegistry() -> [String: Any] {
    SmartBatteryRegistryCache.shared.snapshot()
  }

  private static func readHardwareModel() -> String? {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }
}
