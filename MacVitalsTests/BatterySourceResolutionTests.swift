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
}
