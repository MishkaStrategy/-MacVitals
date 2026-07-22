import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

nonisolated struct DiagnosticBundle: Codable, Sendable, Equatable {
  let schemaVersion: Int
  let generatedAt: Date
  let appVersion: String
  let appBuild: String
  let osVersion: String
  let architecture: String
  let systemUptimeSeconds: TimeInterval
  let snapshot: SystemSnapshot
  let privacyNotice: String
}

nonisolated enum DiagnosticBundleFactory {
  static let schemaVersion = 1

  static func make(
    snapshot: SystemSnapshot,
    generatedAt: Date = Date(),
    appVersion: String,
    appBuild: String,
    osVersion: String,
    architecture: String,
    systemUptimeSeconds: TimeInterval
  ) -> DiagnosticBundle {
    DiagnosticBundle(
      schemaVersion: schemaVersion,
      generatedAt: generatedAt,
      appVersion: appVersion,
      appBuild: appBuild,
      osVersion: osVersion,
      architecture: architecture,
      systemUptimeSeconds: max(0, systemUptimeSeconds),
      snapshot: snapshot,
      privacyNotice:
        "Redacted: no username, home path, serial numbers, Apple ID, documents, or network data")
  }
}

enum DiagnosticReportBuilder {
  @MainActor static func export(snapshot: SystemSnapshot) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue =
      "MacVitals-Support-\(ISO8601DateFormatter().string(from: Date())).json"
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }

    let info = Bundle.main.infoDictionary
    let bundle = DiagnosticBundleFactory.make(
      snapshot: snapshot,
      appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
      appBuild: info?["CFBundleVersion"] as? String ?? "unknown",
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      architecture: architecture(),
      systemUptimeSeconds: ProcessInfo.processInfo.systemUptime)

    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(bundle).write(to: url, options: .atomic)
    } catch {
      Logger.diagnostics.error("Export failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  nonisolated private static func architecture() -> String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return "unknown"
    #endif
  }
}
