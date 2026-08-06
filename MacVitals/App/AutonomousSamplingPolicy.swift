import Foundation

nonisolated enum AutonomousSamplingPolicy {
  static var isEnabled: Bool {
    isEnabled(
      environment: ProcessInfo.processInfo.environment,
      arguments: ProcessInfo.processInfo.arguments)
  }

  static func isEnabled(
    environment: [String: String],
    arguments: [String]
  ) -> Bool {
    if environment["MACVITALS_DISABLE_AUTONOMOUS_SAMPLING"] == "1" {
      return false
    }

    let testEnvironmentKeys = [
      "XCTestConfigurationFilePath",
      "XCTestBundlePath",
      "XCTestSessionIdentifier",
      "XCInjectBundleInto",
    ]
    if testEnvironmentKeys.contains(where: { environment[$0] != nil }) {
      return false
    }

    if arguments.contains(where: { argument in
      argument == "-XCTest" || argument.hasSuffix(".xctest")
    }) {
      return false
    }

    return true
  }
}
