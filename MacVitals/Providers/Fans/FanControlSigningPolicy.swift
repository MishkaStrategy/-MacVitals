import Foundation
import Security

nonisolated struct FanControlSigningFacts: Sendable, Equatable {
  let identifier: String
  let teamIdentifier: String
  let leafCommonName: String
  let trustValid: Bool
  let getTaskAllow: Bool
}

nonisolated enum FanControlSigningPolicy {
  static let mainApplicationIdentifier = "com.mishkacher.MacVitals"
  static let helperIdentifier = "com.mishkacher.MacVitals.FanControl"
  private static let developerIDPrefix = "Developer ID Application: "

  static func accepts(
    _ facts: FanControlSigningFacts,
    expectedIdentifier: String,
    expectedTeamIdentifier: String
  ) -> Bool {
    guard facts.trustValid,
      !facts.getTaskAllow,
      facts.identifier == expectedIdentifier,
      facts.teamIdentifier == expectedTeamIdentifier,
      !expectedTeamIdentifier.isEmpty,
      facts.leafCommonName.hasPrefix(developerIDPrefix),
      facts.leafCommonName.hasSuffix(" (\(expectedTeamIdentifier))")
    else { return false }
    return true
  }
}

nonisolated enum FanControlCodeSigning {
  static func currentFacts() -> FanControlSigningFacts? {
    var dynamicCode: SecCode?
    guard SecCodeCopySelf([], &dynamicCode) == errSecSuccess,
      let dynamicCode
    else { return nil }
    return facts(dynamicCode: dynamicCode)
  }

  static func facts(pid: pid_t) -> FanControlSigningFacts? {
    guard pid > 0 else { return nil }
    let attributes = [kSecGuestAttributePid as String: pid] as CFDictionary
    var dynamicCode: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &dynamicCode) == errSecSuccess,
      let dynamicCode
    else { return nil }
    return facts(dynamicCode: dynamicCode)
  }

  private static func facts(dynamicCode: SecCode) -> FanControlSigningFacts? {
    guard SecCodeCheckValidity(dynamicCode, [], nil) == errSecSuccess else { return nil }

    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess,
      let staticCode
    else { return nil }

    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
      let values = information as? [String: Any],
      let identifier = values[kSecCodeInfoIdentifier as String] as? String,
      let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
      !identifier.isEmpty,
      !team.isEmpty,
      let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate],
      let leaf = certificates.first,
      let leafCommonName = commonName(of: leaf)
    else { return nil }

    let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
    let getTaskAllow = entitlements?["com.apple.security.get-task-allow"] as? Bool ?? false

    return FanControlSigningFacts(
      identifier: identifier,
      teamIdentifier: team,
      leafCommonName: leafCommonName,
      trustValid: evaluateTrust(certificates),
      getTaskAllow: getTaskAllow)
  }

  private static func commonName(of certificate: SecCertificate) -> String? {
    var commonName: CFString?
    guard SecCertificateCopyCommonName(certificate, &commonName) == errSecSuccess,
      let commonName
    else { return nil }
    return commonName as String
  }

  private static func evaluateTrust(_ certificates: [SecCertificate]) -> Bool {
    guard !certificates.isEmpty else { return false }
    let policy = SecPolicyCreateCodeSigning()
    var trust: SecTrust?
    guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess,
      let trust
    else { return false }
    SecTrustSetNetworkFetchAllowed(trust, false)
    return SecTrustEvaluateWithError(trust, nil)
  }
}
