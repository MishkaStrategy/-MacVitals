import XCTest
@testable import MacVitals

final class DiagnosticBundleFactoryTests: XCTestCase {
  func testFactoryIncludesVersionedMetadataAndClampsUptime() {
    let generatedAt = Date(timeIntervalSince1970: 123)
    let bundle = DiagnosticBundleFactory.make(
      snapshot: .empty,
      generatedAt: generatedAt,
      appVersion: "1.0.0",
      appBuild: "7",
      osVersion: "macOS Test",
      architecture: "arm64",
      systemUptimeSeconds: -5)

    XCTAssertEqual(bundle.schemaVersion, 1)
    XCTAssertEqual(bundle.generatedAt, generatedAt)
    XCTAssertEqual(bundle.appVersion, "1.0.0")
    XCTAssertEqual(bundle.appBuild, "7")
    XCTAssertEqual(bundle.osVersion, "macOS Test")
    XCTAssertEqual(bundle.architecture, "arm64")
    XCTAssertEqual(bundle.systemUptimeSeconds, 0)
    XCTAssertTrue(bundle.privacyNotice.contains("no username"))
  }
}
