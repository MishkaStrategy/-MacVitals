import XCTest
@testable import MacVitals

final class MemoryPressureMonitorTests: XCTestCase {
  func testCriticalPressureHasHighestPrecedence() {
    XCTAssertEqual(
      MemoryPressureMapper.level(normal: true, warning: true, critical: true),
      .critical)
  }

  func testWarningPressureOverridesNormal() {
    XCTAssertEqual(
      MemoryPressureMapper.level(normal: true, warning: true, critical: false),
      .warning)
  }

  func testNormalPressureMapsDirectly() {
    XCTAssertEqual(
      MemoryPressureMapper.level(normal: true, warning: false, critical: false),
      .normal)
  }

  func testMissingPressureFlagsRemainUnknown() {
    XCTAssertEqual(
      MemoryPressureMapper.level(normal: false, warning: false, critical: false),
      .unknown)
  }
}
