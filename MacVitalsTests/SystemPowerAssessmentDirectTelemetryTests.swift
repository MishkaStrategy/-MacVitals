import XCTest
@testable import MacVitals

final class SystemPowerAssessmentDirectTelemetryTests: XCTestCase {
  func testDirectTelemetryOverridesBatteryFallback() {
    let assessment = PowerAssessment(
      status: .sufficient,
      confidence: 0.5,
      batteryPowerWatts: 8,
      estimatedSystemPowerWatts: nil,
      powerBalanceWatts: nil,
      explanation: "adapter")

    let resolved = SystemPowerAssessmentResolver.resolve(
      assessment: assessment,
      battery: nil,
      externalPowerState: .connected,
      directSystemPowerWatts: 23.75)

    XCTAssertEqual(resolved.estimatedSystemPowerWatts, 23.75)
    XCTAssertEqual(resolved.confidence, 1)
  }

  func testRejectsImplausibleDirectTelemetry() {
    let assessment = PowerAssessment(
      status: .unknown,
      confidence: 0,
      batteryPowerWatts: nil,
      estimatedSystemPowerWatts: nil,
      powerBalanceWatts: nil,
      explanation: "unknown")

    let resolved = SystemPowerAssessmentResolver.resolve(
      assessment: assessment,
      battery: nil,
      externalPowerState: .connected,
      directSystemPowerWatts: 900)

    XCTAssertNil(resolved.estimatedSystemPowerWatts)
  }
}
