import XCTest

@testable import MacVitals

final class PowerFlowDisplayTests: XCTestCase {
  func testBatteryPowerFlowDistinguishesDischargeChargeZeroAndUnavailable() {
    XCTAssertEqual(BatteryPowerFlowState.resolve(-4.2), .supportingSystem)
    XCTAssertEqual(BatteryPowerFlowState.resolve(3.5), .charging)
    XCTAssertEqual(BatteryPowerFlowState.resolve(0), .idle)
    XCTAssertEqual(BatteryPowerFlowState.resolve(-0.0), .idle)
    XCTAssertEqual(BatteryPowerFlowState.resolve(nil), .unavailable)
    XCTAssertEqual(BatteryPowerFlowState.resolve(.nan), .unavailable)
    XCTAssertEqual(BatteryPowerFlowState.resolve(.infinity), .unavailable)
    XCTAssertEqual(BatteryPowerFlowState.resolve(-Double.infinity), .unavailable)
  }

  func testBatteryPowerFlowProvidesAccurateDisplayMetadata() {
    XCTAssertEqual(BatteryPowerFlowState.supportingSystem.displayName, "Supporting system")
    XCTAssertEqual(BatteryPowerFlowState.supportingSystem.symbolName, "arrow.right")
    XCTAssertEqual(BatteryPowerFlowState.charging.displayName, "Charging")
    XCTAssertEqual(BatteryPowerFlowState.charging.symbolName, "arrow.left")
    XCTAssertEqual(BatteryPowerFlowState.idle.displayName, "No net battery flow")
    XCTAssertEqual(BatteryPowerFlowState.idle.symbolName, "minus")
    XCTAssertEqual(BatteryPowerFlowState.unavailable.displayName, "Unknown")
    XCTAssertEqual(BatteryPowerFlowState.unavailable.symbolName, "arrow.left.and.right")
  }

  func testGPUMemoryDisplayDoesNotGuessWhenCapabilityIsUnavailable() {
    XCTAssertEqual(
      GPUMemoryDisplayText.summary(hasUnifiedMemory: true),
      "unified memory")
    XCTAssertEqual(
      GPUMemoryDisplayText.summary(hasUnifiedMemory: false),
      "discrete memory")
    XCTAssertEqual(
      GPUMemoryDisplayText.summary(hasUnifiedMemory: nil),
      "memory type unavailable")
  }
}
