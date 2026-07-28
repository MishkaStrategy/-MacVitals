import Security
import XCTest

@testable import MacVitals

final class FanControlSigningPolicyTests: XCTestCase {
  private let team = "ABCDE12345"

  func testAcceptsValidatedDeveloperIDMainApplication() {
    XCTAssertTrue(
      FanControlSigningPolicy.accepts(
        facts(identifier: FanControlSigningPolicy.mainApplicationIdentifier),
        expectedIdentifier: FanControlSigningPolicy.mainApplicationIdentifier,
        expectedTeamIdentifier: team))
  }

  func testAcceptsValidatedDeveloperIDHelper() {
    XCTAssertTrue(
      FanControlSigningPolicy.accepts(
        facts(identifier: FanControlSigningPolicy.helperIdentifier),
        expectedIdentifier: FanControlSigningPolicy.helperIdentifier,
        expectedTeamIdentifier: team))
  }

  func testDeveloperIDRequirementsCompileForBothXPCPeers() throws {
    for identifier in [
      FanControlSigningPolicy.mainApplicationIdentifier,
      FanControlSigningPolicy.helperIdentifier,
    ] {
      let source = try XCTUnwrap(
        FanControlCodeSigning.developerIDRequirementSource(
          identifier: identifier,
          teamIdentifier: team))
      XCTAssertTrue(source.contains("anchor apple generic"))
      XCTAssertTrue(source.contains("anchor trusted"))
      XCTAssertTrue(source.contains("1.2.840.113635.100.6.2.6"))
      XCTAssertTrue(source.contains("1.2.840.113635.100.6.1.13"))
      XCTAssertTrue(source.contains(identifier))
      XCTAssertTrue(source.contains(team))

      var requirement: SecRequirement?
      XCTAssertEqual(
        SecRequirementCreateWithString(source as CFString, [], &requirement),
        errSecSuccess)
      XCTAssertNotNil(requirement)
    }
  }

  func testRequirementSourceRejectsUnapprovedIdentifierAndInvalidTeam() {
    XCTAssertNil(
      FanControlCodeSigning.developerIDRequirementSource(
        identifier: "com.example.Impostor",
        teamIdentifier: team))
    XCTAssertNil(
      FanControlCodeSigning.developerIDRequirementSource(
        identifier: FanControlSigningPolicy.mainApplicationIdentifier,
        teamIdentifier: "invalid"))
  }

  func testRejectsAppleDevelopmentOrDistributionRequirementMismatch() {
    XCTAssertFalse(
      acceptsMain(
        facts(
          identifier: FanControlSigningPolicy.mainApplicationIdentifier,
          developerIDRequirementValid: false)))
  }

  func testRejectsGetTaskAllow() {
    XCTAssertFalse(
      acceptsMain(
        facts(
          identifier: FanControlSigningPolicy.mainApplicationIdentifier,
          getTaskAllow: true)))
  }

  func testRejectsWrongBundleIdentifier() {
    XCTAssertFalse(
      acceptsMain(facts(identifier: "com.example.Impostor")))
  }

  func testRejectsWrongTeamIdentifier() {
    XCTAssertFalse(
      acceptsMain(
        FanControlSigningFacts(
          identifier: FanControlSigningPolicy.mainApplicationIdentifier,
          teamIdentifier: "OTHER12345",
          developerIDRequirementValid: true,
          getTaskAllow: false)))
  }

  func testRejectsEmptyExpectedTeamIdentifier() {
    XCTAssertFalse(
      FanControlSigningPolicy.accepts(
        facts(identifier: FanControlSigningPolicy.mainApplicationIdentifier),
        expectedIdentifier: FanControlSigningPolicy.mainApplicationIdentifier,
        expectedTeamIdentifier: ""))
  }

  func testTeamIdentifierRequiresTenUppercaseAlphanumericCharacters() {
    XCTAssertTrue(FanControlSigningPolicy.validTeamIdentifier("ABCDE12345"))
    XCTAssertTrue(FanControlSigningPolicy.validTeamIdentifier("1234567890"))
    XCTAssertFalse(FanControlSigningPolicy.validTeamIdentifier("ABCDE1234"))
    XCTAssertFalse(FanControlSigningPolicy.validTeamIdentifier("ABCDE123456"))
    XCTAssertFalse(FanControlSigningPolicy.validTeamIdentifier("abcde12345"))
    XCTAssertFalse(FanControlSigningPolicy.validTeamIdentifier("ABCDE-2345"))
    XCTAssertFalse(FanControlSigningPolicy.validTeamIdentifier("ABCDE 2345"))
  }

  private func acceptsMain(_ signingFacts: FanControlSigningFacts) -> Bool {
    FanControlSigningPolicy.accepts(
      signingFacts,
      expectedIdentifier: FanControlSigningPolicy.mainApplicationIdentifier,
      expectedTeamIdentifier: team)
  }

  private func facts(
    identifier: String,
    developerIDRequirementValid: Bool = true,
    getTaskAllow: Bool = false
  ) -> FanControlSigningFacts {
    FanControlSigningFacts(
      identifier: identifier,
      teamIdentifier: team,
      developerIDRequirementValid: developerIDRequirementValid,
      getTaskAllow: getTaskAllow)
  }
}
