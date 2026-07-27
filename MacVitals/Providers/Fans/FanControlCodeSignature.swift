import Foundation
import Security

nonisolated struct FanControlSigningFacts: Sendable, Equatable {
  let identifier: String
  let teamIdentifier: String
  let leafCertificateCommonName: String
  let trustIsValid: Bool
  let getTaskAllow: Bool
}

nonisolated enum FanControlCodeSignaturePolicy {
  static let mainApplicationIdentifier = "com.mishkacher.MacVitals"
  static let helperIdentifier = "com.mishkacher.MacVitals.FanControl"
  static let developerIDCommonNamePrefix = "Developer ID Application:"

  static func acceptsDeveloperIDApplication(
    _ facts: FanControlSigningFacts,
    expectedIdentifier: String,
    expectedTeamIdentifier: String? = nil
  ) -> Bool {
    guard facts.identifier == expectedIdentifier,
      !facts.teamIdentifier.isEmpty,
      facts.leafCertificateCommonName.hasPrefix(developerIDCommonNamePrefix),
      facts.trustIsValid,
      !facts.getTaskAllow
    else { return false }
    if let expectedTeamIdentifier {
      return facts.teamIdentifier == expectedTeamIdentifier
    }
    return true
  }
}

nonisolated enum FanControlCodeSignatureReader {
  static func currentProcess() -> FanControlSigningFacts? {
    var dynamicCode: SecCode?
    guard SecCodeCopySelf([], &dynamicCode) == errSecSuccess,
      let dynamicCode,
      SecCodeCheckValidity(dynamicCode, [], nil) == errSecSuccess
    else { return nil }
    return signingFacts(dynamicCode: dynamicCode)
  }

  static func process(pid: pid_t) -> FanControlSigningFacts? {
    guard pid > 0 else { return nil }
    let attributes = [kSecGuestAttributePid as String: pid] as CFDictionary
    var dynamicCode: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &dynamicCode) == errSecSuccess,
      let dynamicCode,
      SecCodeCheckValidity(dynamicCode, [], nil) == errSecSuccess
    else { return nil }
    return signingFacts(dynamicCode: dynamicCode)
  }

  private static func signingFacts(dynamicCode: SecCode) -> FanControlSigningFacts? {
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess,
      let staticCode
    else { return nil }

    let flags = SecCSFlags(
      rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
    var information: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
      let values = information as? [String: Any],
      let identifier = values[kSecCodeInfoIdentifier as String] as? String,
      let teamIdentifier = values[kSecCodeInfoTeamIdentifier as String] as? String,
      let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate],
      let leafCertificate = certificates.first,
      let commonName = certificateCommonName(leafCertificate),
      let trust = values[kSecCodeInfoTrust as String] as? SecTrust
    else { return nil }

    let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
    let getTaskAllow = entitlements?["get-task-allow"] as? Bool ?? false
    return FanControlSigningFacts(
      identifier: identifier,
      teamIdentifier: teamIdentifier,
      leafCertificateCommonName: commonName,
      trustIsValid: SecTrustEvaluateWithError(trust, nil),
      getTaskAllow: getTaskAllow)
  }

  private static func certificateCommonName(_ certificate: SecCertificate) -> String? {
    var commonName: CFString?
    guard SecCertificateCopyCommonName(certificate, &commonName) == errSecSuccess,
      let commonName
    else { return nil }
    return commonName as String
  }
}
