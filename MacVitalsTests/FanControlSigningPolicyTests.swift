import XCTest

@testable import MacVitals

final class FanControlSigningPolicyTests: XCTestCase {
  private let team = "ABCDE12345"

  func testAcceptsTrustedDeveloperIDMainApplication() {
    XCTAssertTrue(
      FanControlSigningPolicy.accepts(
        facts(
          identifier: FanControlSigningPolicy.mainApplicationIdentifier,
          commonName: "Developer ID Application: MacVitals Developer (ABCDE12345)"),
        expectedIdentifier: FanControlSigningPolicy.mainApplicationIdentifier,
        expectedTeamIdentifier: team))
  }

  func testAcceptsTrustedDeveloperIDHelper() {
    XCTAssertTrue(
      FanControlSigningPolicy.accepts(
        facts(
          identifier: FanControlSigningPolicy.helperIdentifier,
          commonName: "Developer ID Application: MacVitals Developer (ABCDE12345)"),
        expectedIdentifier: FanControlSigningPolicy.helperIdentifier,
        expectedTeamIdentifier: team))
  }

  func testRejectsAppleDevelopmentIdentity() {
    XCTAssertFalse(
      acceptsMain(
        facts(
          identifier: FanControlSigningPolicy.mainApplicationIdentifier,
          commonName: "Apple Development: MacVitals Developer (ABCDE12345)")))
  }

  func testRejectsAppleDistributionIdentity() {
    XCTAssertFalse(
      acceptsMain(
        facts(
          identifier: FanControlSigningPolicy.mainApplicationIdentifier,
          commonName: "Apple Distribution: MacVitals Developer (ABCDE12345)")))
  }

  func testRejectsGetTaskAllow() {
    XCTAssertFalse(
      acceptsMain(
        facts(
          identifier: FanControlSigningPolicy.mainApplicationIdentifier,
          commonName: "Developer ID Application: MacVitals Developer (ABCDE12345)",
          getTaskAllow: true)))
  }

  func testRejectsUntrustedCertificateChain() {
    XCTAssertFalse(
      acceptsMain(
        facts(
          identifier: FanControlSigningPolicy.mainApplicationIdentifier,
          commonName: "Developer ID Application: MacVitals Developer (ABCDE12345)",
          trustValid: false)))
  }

  func testRejectsWrongBundleIdentifier() {
    XCTAssertFalse(
      acceptsMain(
        facts(
          identifier: "com.example.Impostor",
          commonName: "Developer ID Application: MacVitals Developer (ABCDE12345)")))
  }

  func testRejectsWrongTeamIdentifier() {
    XCTAssertFalse(
      acceptsMain(
        FanControlSigningFacts(
          identifier: FanControlSigningPolicy.mainApplicationIdentifier,
          teamIdentifier: "OTHER12345",
          leafCommonName: "Developer ID Application: Other Developer (OTHER12345)",
          trustValid: true,
          getTaskAllow: false)))
  }

  func testRejectsDeveloperIDCommonNameForDifferentTeam() {
    XCTAssertFalse(
      acceptsMain(
        facts(
          identifier: FanControlSigningPolicy.mainApplicationIdentifier,
          commonName: "Developer ID Application: Other Developer (OTHER12345)")))
  }

  func testRejectsEmptyExpectedTeamIdentifier() {
    XCTAssertFalse(
      FanControlSigningPolicy.accepts(
        facts(
          identifier: FanControlSigningPolicy.mainApplicationIdentifier,
          commonName: "Developer ID Application: MacVitals Developer (ABCDE12345)"),
        expectedIdentifier: FanControlSigningPolicy.mainApplicationIdentifier,
        expectedTeamIdentifier: ""))
  }

  private func acceptsMain(_ signingFacts: FanControlSigningFacts) -> Bool {
    FanControlSigningPolicy.accepts(
      signingFacts,
      expectedIdentifier: FanControlSigningPolicy.mainApplicationIdentifier,
      expectedTeamIdentifier: team)
  }

  private func facts(
    identifier: String,
    commonName: String,
    trustValid: Bool = true,
    getTaskAllow: Bool = false
  ) -> FanControlSigningFacts {
    FanControlSigningFacts(
      identifier: identifier,
      teamIdentifier: team,
      leafCommonName: commonName,
      trustValid: trustValid,
      getTaskAllow: getTaskAllow)
  }
}
