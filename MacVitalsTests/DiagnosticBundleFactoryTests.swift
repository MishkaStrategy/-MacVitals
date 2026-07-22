import XCTest
@testable import MacVitals

final class DiagnosticBundleFactoryTests: XCTestCase {
  func testFactoryIncludesVersionedMetadataSamplingHealthAndClampsUptime() {
    let generatedAt = Date(timeIntervalSince1970: 123)
    let timings = SamplingTimings(
      cpuMilliseconds: 1,
      memoryMilliseconds: 2,
      batteryMilliseconds: 3,
      adapterMilliseconds: 4,
      gpuMilliseconds: 5,
      powerModelMilliseconds: 6,
      totalMilliseconds: 25)
    let health = SamplingHealth(timings: timings, configuredIntervalSeconds: 2)
    let bundle = DiagnosticBundleFactory.make(
      snapshot: .empty,
      samplingHealth: health,
      generatedAt: generatedAt,
      appVersion: "1.0.0",
      appBuild: "7",
      osVersion: "macOS Test",
      architecture: "arm64",
      systemUptimeSeconds: -5)

    XCTAssertEqual(bundle.schemaVersion, 2)
    XCTAssertEqual(bundle.generatedAt, generatedAt)
    XCTAssertEqual(bundle.appVersion, "1.0.0")
    XCTAssertEqual(bundle.appBuild, "7")
    XCTAssertEqual(bundle.osVersion, "macOS Test")
    XCTAssertEqual(bundle.architecture, "arm64")
    XCTAssertEqual(bundle.systemUptimeSeconds, 0)
    XCTAssertEqual(bundle.samplingHealth, health)
    XCTAssertTrue(bundle.privacyNotice.contains("no username"))
  }
}
