import XCTest

@testable import MacVitals

final class FanControlCodeSignaturePolicyTests: XCTestCase {
  func testAcceptsTrustedDeveloperIDApplicationWithoutDebugEntitlement() {
    let facts = makeFacts()
    XCTAssertTrue(
      FanControlCodeSignaturePolicy.acceptsDeveloperIDApplication(
        facts,
        expectedIdentifier: FanControlCodeSignaturePolicy.mainApplicationIdentifier,
        expectedTeamIdentifier: "TEAM123456"))
  }

  func testRejectsAppleDevelopmentAndAdHocStyleIdentities() {
    for commonName in [
      "Apple Development: Example Developer (TEAM123456)",
      "Apple Distribution: Example Company (TEAM123456)",
      "Mac Developer: Example Developer (TEAM123456)",
      "",
    ] {
      XCTAssertFalse(
        FanControlCodeSignaturePolicy.acceptsDeveloperIDApplication(
          makeFacts(commonName: commonName),
          expectedIdentifier: FanControlCodeSignaturePolicy.mainApplicationIdentifier))
    }
  }

  func testRejectsGetTaskAllowInvalidTrustWrongIdentifierAndWrongTeam() {
    let variants = [
      makeFacts(getTaskAllow: true),
      makeFacts(trustIsValid: false),
      makeFacts(identifier: "com.example.Other"),
      makeFacts(teamIdentifier: "OTHERTEAM1"),
    ]

    for facts in variants {
      XCTAssertFalse(
        FanControlCodeSignaturePolicy.acceptsDeveloperIDApplication(
          facts,
          expectedIdentifier: FanControlCodeSignaturePolicy.mainApplicationIdentifier,
          expectedTeamIdentifier: "TEAM123456"))
    }
  }

  func testHelperAndApplicationIdentifiersAreNotInterchangeable() {
    let helper = makeFacts(identifier: FanControlCodeSignaturePolicy.helperIdentifier)
    XCTAssertTrue(
      FanControlCodeSignaturePolicy.acceptsDeveloperIDApplication(
        helper,
        expectedIdentifier: FanControlCodeSignaturePolicy.helperIdentifier))
    XCTAssertFalse(
      FanControlCodeSignaturePolicy.acceptsDeveloperIDApplication(
        helper,
        expectedIdentifier: FanControlCodeSignaturePolicy.mainApplicationIdentifier))
  }

  private func makeFacts(
    identifier: String = FanControlCodeSignaturePolicy.mainApplicationIdentifier,
    teamIdentifier: String = "TEAM123456",
    commonName: String = "Developer ID Application: Example Company (TEAM123456)",
    trustIsValid: Bool = true,
    getTaskAllow: Bool = false
  ) -> FanControlSigningFacts {
    FanControlSigningFacts(
      identifier: identifier,
      teamIdentifier: teamIdentifier,
      leafCertificateCommonName: commonName,
      trustIsValid: trustIsValid,
      getTaskAllow: getTaskAllow)
  }
}
