import Foundation
import XCTest
@testable import MacVitals

final class GPUUtilizationNormalizerTests: XCTestCase {
  func testReadsKnownUtilizationKeys() {
    XCTAssertEqual(
      GPUUtilizationNormalizer.percentage(
        from: ["Device Utilization %": NSNumber(value: 37.5)]),
      37.5)
    XCTAssertEqual(
      GPUUtilizationNormalizer.percentage(
        from: ["GPU Activity(%)": NSNumber(value: 82)]),
      82)
  }

  func testRejectsInvalidAndBooleanValues() {
    XCTAssertNil(
      GPUUtilizationNormalizer.percentage(
        from: ["Device Utilization %": NSNumber(value: true)]))
    XCTAssertNil(
      GPUUtilizationNormalizer.percentage(
        from: ["Device Utilization %": NSNumber(value: 150)]))
  }

  func testChoosesHighestValidReadingAcrossAccelerators() {
    XCTAssertEqual(
      GPUUtilizationNormalizer.percentage(
        from: [
          ["Device Utilization %": NSNumber(value: 12)],
          ["Renderer Utilization %": NSNumber(value: 44)],
        ]),
      44)
  }
}
