import Foundation

nonisolated final class FanProvider: @unchecked Sendable {
  typealias ConnectionFactory = @Sendable () throws -> any AppleSMCReading

  private let factory: ConnectionFactory
  private let lock = NSLock()
  private var connection: (any AppleSMCReading)?

  init(factory: @escaping ConnectionFactory = { try AppleSMCConnection() }) {
    self.factory = factory
  }

  func resetConnection() {
    lock.withLock { connection = nil }
  }

  func sample(now: Date = Date()) -> MetricValue<FanStats> {
    do {
      let source = try reader()
      guard let rawCount = try? source.readKey("FNum"),
        let decodedCount = AppleSMCDataDecoder.unsignedInteger(rawCount),
        let count = FanValueNormalizer.fanCount(decodedCount)
      else {
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

      guard count > 0 else {
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

      let readings = (0..<count).compactMap { index in
        reading(index: index, source: source)
      }
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
        message: readings.count == count ? nil : "Some fan values are unavailable")
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

  private func reading(index: Int, source: any AppleSMCReading) -> FanReading? {
    FanValueNormalizer.reading(
      index: index,
      current: number(key: "F\(index)Ac", source: source),
      target: number(key: "F\(index)Tg", source: source),
      minimum: number(key: "F\(index)Mn", source: source),
      maximum: number(key: "F\(index)Mx", source: source),
      mode: mode(index: index, source: source))
  }

  private func number(key: String, source: any AppleSMCReading) -> Double? {
    guard let raw = try? source.readKey(key) else { return nil }
    return AppleSMCDataDecoder.number(raw)
  }

  private func mode(index: Int, source: any AppleSMCReading) -> FanMode {
    for key in ["F\(index)md", "F\(index)Md"] {
      guard let raw = try? source.readKey(key), let value = raw.bytes.first else { continue }
      return value == 0 ? .automatic : .manual
    }
    return .unknown
  }
}
