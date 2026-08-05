import XCTest
@testable import MacVitals

final class FanProviderTopologyCacheTests: XCTestCase {
  func testFanCountIsReadOnceUntilConnectionReset() {
    let source = CountingFanSMC(values: [
      "FNum": AppleSMCKeyValue(bytes: [1], dataType: "ui8 "),
      "F0Ac": float(2_100),
      "F0Tg": float(2_300),
      "F0Mn": float(1_200),
      "F0Mx": float(6_000),
      "F0md": AppleSMCKeyValue(bytes: [0], dataType: "ui8 "),
    ])
    let provider = FanProvider(factory: { source })

    _ = provider.sample()
    _ = provider.sample()
    XCTAssertEqual(source.readCount(for: "FNum"), 1)
    XCTAssertEqual(source.readCount(for: "F0Ac"), 2)

    provider.resetConnection()
    _ = provider.sample()
    XCTAssertEqual(source.readCount(for: "FNum"), 2)
  }

  private func float(_ value: Float) -> AppleSMCKeyValue {
    var value = value
    return AppleSMCKeyValue(bytes: withUnsafeBytes(of: &value) { Array($0) }, dataType: "flt ")
  }
}

private final class CountingFanSMC: AppleSMCReading, @unchecked Sendable {
  private let values: [String: AppleSMCKeyValue]
  private let lock = NSLock()
  private var counts: [String: Int] = [:]

  init(values: [String: AppleSMCKeyValue]) {
    self.values = values
  }

  func readKey(_ key: String) throws -> AppleSMCKeyValue {
    lock.withLock { counts[key, default: 0] += 1 }
    guard let value = values[key] else { throw AppleSMCError.firmware(0x84) }
    return value
  }

  func readCount(for key: String) -> Int {
    lock.withLock { counts[key, default: 0] }
  }
}
