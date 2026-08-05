import Foundation

nonisolated final class FanProvider: @unchecked Sendable {
  typealias ConnectionFactory = @Sendable () throws -> any AppleSMCReading

  private struct FanKeys: Sendable {
    let index: Int
    let current: String
    let target: String
    let minimum: String
    let maximum: String
    let modeLowercase: String
    let modeUppercase: String
  }

  private let factory: ConnectionFactory
  private let lock = NSLock()
  private var connection: (any AppleSMCReading)?
  private var cachedFanKeys: [FanKeys]?

  init(factory: @escaping ConnectionFactory = { try AppleSMCConnection() }) {
    self.factory = factory
  }

  func resetConnection() {
    lock.withLock {
      connection = nil
      cachedFanKeys = nil
    }
  }

  func sample(now: Date = Date()) -> MetricValue<FanStats> {
    do {
      let source = try reader()
      guard let keys = topology(source: source) else {
        return .init(
          value: nil,
          unit: .rpm,
          availability: .providerError,
          quality: .unknown,
          source: .appleSMC,
          timestamp: now,
          isEstimated: false,
          message: "Fan count could not be read safely")
      }

      guard !keys.isEmpty else {
        return .init(
          value: FanStats(fans: []),
          unit: .rpm,
          availability: .unsupported,
          quality: .experimental,
          source: .appleSMC,
          timestamp: now,
          isEstimated: false,
          message: "No controllable fan is exposed by AppleSMC")
      }

      let readings = keys.compactMap { reading(keys: $0, source: source) }
      guard !readings.isEmpty else {
        return .init(
          value: nil,
          unit: .rpm,
          availability: .temporarilyUnavailable,
          quality: .unknown,
          source: .appleSMC,
          timestamp: now,
          isEstimated: false,
          message: "Fan RPM values are temporarily unavailable")
      }

      return .init(
        value: FanStats(fans: readings),
        unit: .rpm,
        availability: .available,
        quality: .experimental,
        source: .appleSMC,
        timestamp: now,
        isEstimated: false,
        message: readings.count == keys.count ? nil : "Some fan values are unavailable")
    } catch {
      resetConnection()
      return .init(
        value: nil,
        unit: .rpm,
        availability: .providerError,
        quality: .unknown,
        source: .appleSMC,
        timestamp: now,
        isEstimated: false,
        message: error.localizedDescription)
    }
  }

  private func reader() throws -> any AppleSMCReading {
    try lock.withLock {
      if let connection { return connection }
      let created = try factory()
      connection = created
      return created
    }
  }

  private func topology(source: any AppleSMCReading) -> [FanKeys]? {
    if let cached = lock.withLock({ cachedFanKeys }) {
      return cached
    }

    guard let rawCount = try? source.readKey("FNum"),
      let decodedCount = AppleSMCDataDecoder.unsignedInteger(rawCount),
      let count = FanValueNormalizer.fanCount(decodedCount)
    else {
      return nil
    }

    let keys = (0..<count).map { index in
      FanKeys(
        index: index,
        current: "F\(index)Ac",
        target: "F\(index)Tg",
        minimum: "F\(index)Mn",
        maximum: "F\(index)Mx",
        modeLowercase: "F\(index)md",
        modeUppercase: "F\(index)Md")
    }
    lock.withLock { cachedFanKeys = keys }
    return keys
  }

  private func reading(keys: FanKeys, source: any AppleSMCReading) -> FanReading? {
    FanValueNormalizer.reading(
      index: keys.index,
      current: number(key: keys.current, source: source),
      target: number(key: keys.target, source: source),
      minimum: number(key: keys.minimum, source: source),
      maximum: number(key: keys.maximum, source: source),
      mode: mode(keys: keys, source: source))
  }

  private func number(key: String, source: any AppleSMCReading) -> Double? {
    guard let raw = try? source.readKey(key) else { return nil }
    return AppleSMCDataDecoder.number(raw)
  }

  private func mode(keys: FanKeys, source: any AppleSMCReading) -> FanMode {
    if let raw = try? source.readKey(keys.modeLowercase), let value = raw.bytes.first {
      return FanMode.decodeSMCByte(value)
    }
    if let raw = try? source.readKey(keys.modeUppercase), let value = raw.bytes.first {
      return FanMode.decodeSMCByte(value)
    }
    return .unknown
  }
}
