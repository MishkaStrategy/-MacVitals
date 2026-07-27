import Foundation
import Security

nonisolated struct FanControlSigningFacts: Sendable, Equatable {
  let identifier: String
  let teamIdentifier: String
  let developerIDRequirementValid: Bool
  let getTaskAllow: Bool
}

nonisolated enum FanControlSigningPolicy {
  static let mainApplicationIdentifier = "com.mishkacher.MacVitals"
  static let helperIdentifier = "com.mishkacher.MacVitals.FanControl"

  static func accepts(
    _ facts: FanControlSigningFacts,
    expectedIdentifier: String,
    expectedTeamIdentifier: String
  ) -> Bool {
    guard facts.developerIDRequirementValid,
      !facts.getTaskAllow,
      facts.identifier == expectedIdentifier,
      facts.teamIdentifier == expectedTeamIdentifier,
      validTeamIdentifier(expectedTeamIdentifier)
    else { return false }
    return true
  }

  static func validTeamIdentifier(_ value: String) -> Bool {
    value.count == 10 && value.unicodeScalars.allSatisfy { scalar in
      (65...90).contains(scalar.value) || (48...57).contains(scalar.value)
    }
  }
}

nonisolated enum FanControlCodeSigning {
  private struct Metadata {
    let identifier: String
    let teamIdentifier: String
    let getTaskAllow: Bool
  }

  static func currentFacts() -> FanControlSigningFacts? {
    var dynamicCode: SecCode?
    guard SecCodeCopySelf([], &dynamicCode) == errSecSuccess,
      let dynamicCode
    else { return nil }
    return validatedFacts(dynamicCode: dynamicCode)
  }

  static func facts(pid: pid_t) -> FanControlSigningFacts? {
    guard pid > 0 else { return nil }
    let attributes = [kSecGuestAttributePid as String: pid] as CFDictionary
    var dynamicCode: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &dynamicCode) == errSecSuccess,
      let dynamicCode
    else { return nil }
    return validatedFacts(dynamicCode: dynamicCode)
  }

  static func facts(
    pid: pid_t,
    expectedIdentifier: String,
    expectedTeamIdentifier: String
  ) -> FanControlSigningFacts? {
    guard let signingFacts = facts(pid: pid),
      FanControlSigningPolicy.accepts(
        signingFacts,
        expectedIdentifier: expectedIdentifier,
        expectedTeamIdentifier: expectedTeamIdentifier)
    else { return nil }
    return signingFacts
  }

  private static func validatedFacts(dynamicCode: SecCode) -> FanControlSigningFacts? {
    guard let metadata = metadata(dynamicCode: dynamicCode),
      allowedIdentifier(metadata.identifier)
    else { return nil }

    return FanControlSigningFacts(
      identifier: metadata.identifier,
      teamIdentifier: metadata.teamIdentifier,
      developerIDRequirementValid: satisfiesDeveloperIDRequirement(
        dynamicCode: dynamicCode,
        identifier: metadata.identifier,
        teamIdentifier: metadata.teamIdentifier),
      getTaskAllow: metadata.getTaskAllow)
  }

  private static func metadata(dynamicCode: SecCode) -> Metadata? {
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
      FanControlSigningPolicy.validTeamIdentifier(team)
    else { return nil }

    let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
    return Metadata(
      identifier: identifier,
      teamIdentifier: team,
      getTaskAllow: entitlements?["com.apple.security.get-task-allow"] as? Bool ?? false)
  }

  private static func satisfiesDeveloperIDRequirement(
    dynamicCode: SecCode,
    identifier: String,
    teamIdentifier: String
  ) -> Bool {
    guard allowedIdentifier(identifier),
      FanControlSigningPolicy.validTeamIdentifier(teamIdentifier)
    else { return false }

    let source = """
      anchor apple generic and anchor trusted
      and identifier \"\(identifier)\"
      and certificate 1[field.1.2.840.113635.100.6.2.6] exists
      and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
      and certificate leaf[subject.OU] = \"\(teamIdentifier)\"
      """
    var requirement: SecRequirement?
    guard SecRequirementCreateWithString(source as CFString, [], &requirement) == errSecSuccess,
      let requirement
    else { return false }
    return SecCodeCheckValidity(dynamicCode, [], requirement) == errSecSuccess
  }

  private static func allowedIdentifier(_ identifier: String) -> Bool {
    identifier == FanControlSigningPolicy.mainApplicationIdentifier ||
      identifier == FanControlSigningPolicy.helperIdentifier
  }
}
