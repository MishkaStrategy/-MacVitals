import XCTest

@testable import MacVitals

final class BatterySourceResolutionTests: XCTestCase {
  func testEmptyPowerSourceListIsOnlyAnAbsenceCandidate() {
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

  func testFullyDescribedExternalSourcesWithoutInternalBatteryAreAbsenceCandidate() {
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

  func testHardwareClassificationIsFailClosed() {
    XCTAssertEqual(BatteryHardwareKind.classify(modelIdentifier: "MacBookPro18,2"), .portable)
    XCTAssertEqual(BatteryHardwareKind.classify(modelIdentifier: "MacBookAir10,1"), .portable)
    XCTAssertEqual(BatteryHardwareKind.classify(modelIdentifier: "Macmini9,1"), .desktop)
    XCTAssertEqual(BatteryHardwareKind.classify(modelIdentifier: "MacStudio1,1"), .desktop)
    XCTAssertEqual(BatteryHardwareKind.classify(modelIdentifier: "MacPro7,1"), .desktop)
    XCTAssertEqual(BatteryHardwareKind.classify(modelIdentifier: "iMac21,1"), .desktop)
    XCTAssertEqual(BatteryHardwareKind.classify(modelIdentifier: "VirtualMac2,1"), .unknown)
    XCTAssertEqual(BatteryHardwareKind.classify(modelIdentifier: nil), .unknown)
    XCTAssertEqual(BatteryHardwareKind.classify(modelIdentifier: "  "), .unknown)
  }

  func testBatteryAbsenceRequiresSamplesAndElapsedDuration() {
    var confirmation = BatteryAbsenceConfirmation()
    let start = Date(timeIntervalSince1970: 1_000)

    XCTAssertFalse(
      confirmation.evaluate(
        timestamp: start,
        absenceCandidate: true,
        smartBatteryServiceFound: false))
    XCTAssertFalse(
      confirmation.evaluate(
        timestamp: start.addingTimeInterval(5),
        absenceCandidate: true,
        smartBatteryServiceFound: false))
    XCTAssertTrue(
      confirmation.evaluate(
        timestamp: start.addingTimeInterval(10),
        absenceCandidate: true,
        smartBatteryServiceFound: false))
  }

  func testSmartBatteryServiceCancelsAbsenceConfirmation() {
    var confirmation = BatteryAbsenceConfirmation()
    let start = Date(timeIntervalSince1970: 2_000)

    XCTAssertFalse(
      confirmation.evaluate(
        timestamp: start,
        absenceCandidate: true,
        smartBatteryServiceFound: false))
    XCTAssertFalse(
      confirmation.evaluate(
        timestamp: start.addingTimeInterval(5),
        absenceCandidate: true,
        smartBatteryServiceFound: true))
    XCTAssertNil(confirmation.firstObservedAt)
    XCTAssertEqual(confirmation.sampleCount, 0)
  }

  func testNonCandidateSampleResetsAbsenceConfirmation() {
    var confirmation = BatteryAbsenceConfirmation()
    let start = Date(timeIntervalSince1970: 3_000)

    XCTAssertFalse(
      confirmation.evaluate(
        timestamp: start,
        absenceCandidate: true,
        smartBatteryServiceFound: false))
    XCTAssertFalse(
      confirmation.evaluate(
        timestamp: start.addingTimeInterval(5),
        absenceCandidate: false,
        smartBatteryServiceFound: false))
    XCTAssertNil(confirmation.firstObservedAt)
    XCTAssertEqual(confirmation.sampleCount, 0)
  }

  func testClockRollbackRestartsAbsenceConfirmation() {
    var confirmation = BatteryAbsenceConfirmation()
    let start = Date(timeIntervalSince1970: 4_000)

    XCTAssertFalse(
      confirmation.evaluate(
        timestamp: start,
        absenceCandidate: true,
        smartBatteryServiceFound: false))
    XCTAssertFalse(
      confirmation.evaluate(
        timestamp: start.addingTimeInterval(5),
        absenceCandidate: true,
        smartBatteryServiceFound: false))
    XCTAssertFalse(
      confirmation.evaluate(
        timestamp: start.addingTimeInterval(-10),
        absenceCandidate: true,
        smartBatteryServiceFound: false))
    XCTAssertEqual(confirmation.sampleCount, 1)
    XCTAssertEqual(confirmation.firstObservedAt, start.addingTimeInterval(-10))
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
