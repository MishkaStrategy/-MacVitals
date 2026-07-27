import XCTest
@testable import MacVitals

final class TemperatureValueNormalizerTests: XCTestCase {
  func testAcceptsPlausibleProcessorTemperature() {
    XCTAssertEqual(TemperatureValueNormalizer.processor(72.5), 72.5)
  }

  func testRejectsImplausibleProcessorTemperature() {
    XCTAssertNil(TemperatureValueNormalizer.processor(-20))
    XCTAssertNil(TemperatureValueNormalizer.processor(200))
    XCTAssertNil(TemperatureValueNormalizer.processor(.infinity))
  }

  func testAcceptsPlausibleBatteryTemperature() {
    XCTAssertEqual(TemperatureValueNormalizer.battery(34.25), 34.25)
  }

  func testRejectsImplausibleBatteryTemperature() {
    XCTAssertNil(TemperatureValueNormalizer.battery(-1))
    XCTAssertNil(TemperatureValueNormalizer.battery(101))
    XCTAssertNil(TemperatureValueNormalizer.battery(.nan))
  }
}
