import XCTest
@testable import MacVitals

final class SystemSamplerTests: XCTestCase {
  func testSamplerProducesCoherentHardwareSnapshot() async throws {
    let sampler = SystemSampler()
    let first = await sampler.sample()
    try await Task.sleep(nanoseconds: 100_000_000)
    let second = await sampler.sample()

    XCTAssertGreaterThanOrEqual(second.timestamp, first.timestamp)
    XCTAssertEqual(second.memory.availability, .available)
    XCTAssertGreaterThan(second.memory.value?.physicalBytes ?? 0, 0)
    XCTAssertLessThanOrEqual(second.memory.value?.usedPercent ?? 101, 100)
    XCTAssertNotEqual(second.cpu.availability, .providerError)
    XCTAssertNotEqual(second.gpu.availability, .providerError)
    XCTAssertNotNil(second.power.value)

    let maximumSkew: TimeInterval = 5
    XCTAssertLessThan(abs(second.timestamp.timeIntervalSince(second.memory.timestamp)), maximumSkew)
    XCTAssertLessThan(abs(second.timestamp.timeIntervalSince(second.power.timestamp)), maximumSkew)
  }
}
