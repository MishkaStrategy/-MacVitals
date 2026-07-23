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
  let samplingHealth: SamplingHealth?
  let privacyNotice: String
}

nonisolated enum DiagnosticBundleFactory {
  static let schemaVersion = 2

  static func make(
    snapshot: SystemSnapshot,
    samplingHealth: SamplingHealth? = nil,
    generatedAt: Date = Date(),
    appVersion: String,
    appBuild: String,
    osVersion: String,
    architecture: String,
    systemUptimeSeconds: TimeInterval
  ) -> DiagnosticBundle {
    DiagnosticBundle(
      schemaVersion: schemaVersion,
      generatedAt: validDate(generatedAt),
      appVersion: appVersion,
      appBuild: appBuild,
      osVersion: osVersion,
      architecture: architecture,
      systemUptimeSeconds: finiteNonnegative(systemUptimeSeconds),
      snapshot: DiagnosticSnapshotRedactor.redact(snapshot),
      samplingHealth: samplingHealth,
      privacyNotice:
        "Redacted: no username, home path, serial numbers, stable GPU registry identifiers, Apple ID, documents, or network data"
    )
  }

  private static func validDate(_ value: Date) -> Date {
    value.timeIntervalSinceReferenceDate.isFinite
      ? value
      : Date(timeIntervalSinceReferenceDate: 0)
  }

  private static func finiteNonnegative(_ value: TimeInterval) -> TimeInterval {
    value.isFinite ? max(0, value) : 0
  }
}

nonisolated enum DiagnosticReportFilename {
  static func make(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return "MacVitals-Support-\(formatter.string(from: date)).json"
  }
}

enum DiagnosticReportBuilder {
  @MainActor static func export(
    snapshot: SystemSnapshot,
    samplingHealth: SamplingHealth? = nil
  ) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = DiagnosticReportFilename.make(for: Date())
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }

    let info = Bundle.main.infoDictionary
    let bundle = DiagnosticBundleFactory.make(
      snapshot: snapshot,
      samplingHealth: samplingHealth,
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
      Logger.diagnostics.error(
        "Export failed: \(error.localizedDescription, privacy: .private)")
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
