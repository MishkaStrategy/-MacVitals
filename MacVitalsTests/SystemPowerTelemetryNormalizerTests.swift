import XCTest
@testable import MacVitals

final class SystemPowerTelemetryNormalizerTests: XCTestCase {
  func testConvertsMilliwattsToWatts() {
    let watts = SystemPowerTelemetryNormalizer.watts(
      fromMilliwatts: NSNumber(value: 12_685))
    XCTAssertNotNil(watts)
    XCTAssertEqual(watts ?? 0, 12.685, accuracy: 0.0001)
  }

  func testRejectsNegativeAndImplausibleValues() {
    XCTAssertNil(SystemPowerTelemetryNormalizer.watts(fromMilliwatts: NSNumber(value: -1)))
    XCTAssertNil(SystemPowerTelemetryNormalizer.watts(fromMilliwatts: NSNumber(value: 500_001)))
  }

  func testRejectsNonNumericValue() {
    XCTAssertNil(SystemPowerTelemetryNormalizer.watts(fromMilliwatts: "12685"))
  }
}
