import XCTest

@testable import MacVitals

final class AdapterValueNormalizerTests: XCTestCase {
  func testFiniteNumberAcceptsFiniteNSNumberOnly() {
    XCTAssertEqual(AdapterValueNormalizer.finiteNumber(NSNumber(value: 96)), 96)
    XCTAssertNil(AdapterValueNormalizer.finiteNumber(NSNumber(value: Double.nan)))
    XCTAssertNil(AdapterValueNormalizer.finiteNumber("96"))
    XCTAssertNil(AdapterValueNormalizer.finiteNumber(nil))
  }

  func testRatedPowerBounds() {
    XCTAssertEqual(AdapterValueNormalizer.ratedPowerWatts(140), 140)
    XCTAssertNil(AdapterValueNormalizer.ratedPowerWatts(0))
    XCTAssertNil(AdapterValueNormalizer.ratedPowerWatts(1_001))
    XCTAssertNil(AdapterValueNormalizer.ratedPowerWatts(.infinity))
  }

  func testDocumentedMilliampUnitsConvertExactlyToAmps() {
    XCTAssertEqual(AdapterValueNormalizer.milliampsToAmps(0), 0)
    XCTAssertEqual(AdapterValueNormalizer.milliampsToAmps(5_000), 5)
    XCTAssertEqual(AdapterValueNormalizer.milliampsToAmps(20_000), 20)
    XCTAssertNil(AdapterValueNormalizer.milliampsToAmps(-1))
    XCTAssertNil(AdapterValueNormalizer.milliampsToAmps(20_001))
    XCTAssertNil(AdapterValueNormalizer.milliampsToAmps(.infinity))
  }
}
