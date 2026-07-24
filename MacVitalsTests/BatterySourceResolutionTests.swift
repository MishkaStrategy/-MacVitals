import XCTest

@testable import MacVitals

final class BatterySourceResolutionTests: XCTestCase {
  func testEmptyPowerSourceListMeansNoInternalBattery() {
    XCTAssertEqual(
      BatterySourceResolution.resolve(
        sourceCount: 0,
        classifiedSourceCount: 0,
        internalBatteryFound: false),
      .absent)
  }

  func testUndescribableNonemptySourceListIsProviderError() {
    XCTAssertEqual(
      BatterySourceResolution.resolve(
        sourceCount: 1,
        classifiedSourceCount: 0,
        internalBatteryFound: false),
      .providerError)
  }

  func testPartiallyDescribedSourceListIsProviderError() {
    XCTAssertEqual(
      BatterySourceResolution.resolve(
        sourceCount: 2,
        classifiedSourceCount: 1,
        internalBatteryFound: false),
      .providerError)
  }

  func testFullyDescribedExternalSourcesWithoutInternalBatteryMeanAbsent() {
    XCTAssertEqual(
      BatterySourceResolution.resolve(
        sourceCount: 2,
        classifiedSourceCount: 2,
        internalBatteryFound: false),
      .absent)
  }

  func testInvalidCountsAreProviderErrors() {
    XCTAssertEqual(
      BatterySourceResolution.resolve(
        sourceCount: -1,
        classifiedSourceCount: 0,
        internalBatteryFound: false),
      .providerError)
    XCTAssertEqual(
      BatterySourceResolution.resolve(
        sourceCount: 1,
        classifiedSourceCount: 2,
        internalBatteryFound: false),
      .providerError)
    XCTAssertEqual(
      BatterySourceResolution.resolve(
        sourceCount: 1,
        classifiedSourceCount: 0,
        internalBatteryFound: true),
      .providerError)
  }

  func testInternalBatteryWinsWhenFound() {
    XCTAssertEqual(
      BatterySourceResolution.resolve(
        sourceCount: 1,
        classifiedSourceCount: 1,
        internalBatteryFound: true),
      .present)
  }

  func testBatteryExternalPowerResolutionAcceptsOnlyKnownStates() {
    XCTAssertEqual(
      BatteryExternalPowerResolution.resolve(
        rawState: "AC Power",
        acPowerValue: "AC Power",
        batteryPowerValue: "Battery Power"),
      .connected)
    XCTAssertEqual(
      BatteryExternalPowerResolution.resolve(
        rawState: "Battery Power",
        acPowerValue: "AC Power",
        batteryPowerValue: "Battery Power"),
      .disconnected)
    XCTAssertEqual(
      BatteryExternalPowerResolution.resolve(
        rawState: nil,
        acPowerValue: "AC Power",
        batteryPowerValue: "Battery Power"),
      .unavailable)
    XCTAssertEqual(
      BatteryExternalPowerResolution.resolve(
        rawState: "Unknown",
        acPowerValue: "AC Power",
        batteryPowerValue: "Battery Power"),
      .unavailable)
  }

  func testBatteryExternalPowerResolutionBooleanProjectionIsExplicit() {
    XCTAssertEqual(BatteryExternalPowerResolution.connected.isConnected, true)
    XCTAssertEqual(BatteryExternalPowerResolution.disconnected.isConnected, false)
    XCTAssertNil(BatteryExternalPowerResolution.unavailable.isConnected)
  }
}
