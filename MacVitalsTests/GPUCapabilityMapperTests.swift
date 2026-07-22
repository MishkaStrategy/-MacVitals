import XCTest
@testable import MacVitals

final class GPUCapabilityMapperTests: XCTestCase {
  func testMapsCapabilitiesWithoutInventingUtilization() {
    let stats = GPUCapabilityMapper.makeStats(
      name: "Test GPU",
      registryID: 42,
      hasUnifiedMemory: true,
      isLowPower: true,
      isRemovable: false,
      recommendedWorkingSetBytes: 8_000_000_000)

    XCTAssertEqual(stats.name, "Test GPU")
    XCTAssertEqual(stats.registryID, 42)
    XCTAssertEqual(stats.hasUnifiedMemory, true)
    XCTAssertEqual(stats.isLowPower, true)
    XCTAssertEqual(stats.isRemovable, false)
    XCTAssertEqual(stats.recommendedWorkingSetBytes, 8_000_000_000)
    XCTAssertNil(stats.systemUtilizationPercent)
    XCTAssertEqual(stats.utilizationAvailability, .unsupported)
  }
}
