import XCTest
@testable import MacVitals

final class AdapterValueNormalizerTests: XCTestCase {
  func testFirstFiniteNumberSkipsInvalidValuesAndUsesFallbackKey() {
    let details: [String: Any] = [
      "Primary": NSNumber(value: Double.nan),
      "Fallback": NSNumber(value: 96),
    ]

    XCTAssertEqual(
      AdapterValueNormalizer.firstFiniteNumber(
        keys: ["Missing", "Primary", "Fallback"],
        in: details),
      96)
  }

  func testRatedPowerBounds() {
    XCTAssertEqual(AdapterValueNormalizer.ratedPowerWatts(140), 140)
    XCTAssertNil(AdapterValueNormalizer.ratedPowerWatts(0))
    XCTAssertNil(AdapterValueNormalizer.ratedPowerWatts(1_001))
    XCTAssertNil(AdapterValueNormalizer.ratedPowerWatts(.infinity))
  }

  func testVoltageAndCurrentNormalizeBaseUnitsAndMilliunits() {
    XCTAssertEqual(AdapterValueNormalizer.voltageVolts(20), 20)
    XCTAssertEqual(AdapterValueNormalizer.voltageVolts(20_000), 20)
    XCTAssertNil(AdapterValueNormalizer.voltageVolts(120_000))

    XCTAssertEqual(AdapterValueNormalizer.currentAmperes(5), 5)
    XCTAssertEqual(AdapterValueNormalizer.currentAmperes(5_000), 5)
    XCTAssertNil(AdapterValueNormalizer.currentAmperes(-1))
    XCTAssertNil(AdapterValueNormalizer.currentAmperes(25_000))
  }

  func testTextIsTrimmedRejectedWhenEmptyAndLengthBounded() {
    XCTAssertEqual(AdapterValueNormalizer.text("  Apple  "), "Apple")
    XCTAssertNil(AdapterValueNormalizer.text(" \n "))
    XCTAssertNil(AdapterValueNormalizer.text(42))
    XCTAssertEqual(AdapterValueNormalizer.text(String(repeating: "x", count: 300))?.count, 256)
  }
}
