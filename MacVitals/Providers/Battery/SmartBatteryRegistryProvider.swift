import Foundation
import IOKit

nonisolated final class SmartBatteryRegistryCache: @unchecked Sendable {
  typealias Reader = () -> [String: Any]

  static let shared = SmartBatteryRegistryCache()

  private let freshnessInterval: TimeInterval
  private let reader: Reader
  private let lock = NSLock()
  private var cachedProperties: [String: Any] = [:]
  private var sampledAt: TimeInterval?

  init(
    freshnessInterval: TimeInterval = 0.25,
    reader: Reader? = nil
  ) {
    self.freshnessInterval = max(0, freshnessInterval)
    self.reader = reader ?? Self.readRegistry
  }

  func snapshot(
    now: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) -> [String: Any] {
    lock.withLock {
      if let sampledAt,
        now >= sampledAt,
        now - sampledAt < freshnessInterval
      {
        return cachedProperties
      }

      let properties = reader()
      cachedProperties = properties
      sampledAt = now
      return properties
    }
  }

  func reset() {
    lock.withLock {
      cachedProperties = [:]
      sampledAt = nil
    }
  }

  private static func readRegistry() -> [String: Any] {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault,
      IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return [:] }
    defer { IOObjectRelease(service) }

    var properties: Unmanaged<CFMutableDictionary>?
    guard
      IORegistryEntryCreateCFProperties(
        service,
        &properties,
        kCFAllocatorDefault,
        0) == KERN_SUCCESS,
      let dictionary = properties?.takeRetainedValue() as? [String: Any]
    else { return [:] }
    return dictionary
  }
}
