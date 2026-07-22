import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

nonisolated struct DiagnosticBundle: Codable, Sendable {
    let generatedAt: Date
    let appVersion: String
    let osVersion: String
    let architecture: String
    let snapshot: SystemSnapshot
    let privacyNotice: String
}

enum DiagnosticReportBuilder {
    @MainActor static func export(snapshot: SystemSnapshot) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "MacVitals-Support-\(ISO8601DateFormatter().string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = DiagnosticBundle(generatedAt: Date(),
                                      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                                      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                      architecture: architecture(), snapshot: snapshot,
                                      privacyNotice: "Redacted: no username, home path, serial numbers, Apple ID, documents, or network data")
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(bundle).write(to: url, options: .atomic)
        } catch { Logger.diagnostics.error("Export failed: \(error.localizedDescription, privacy: .public)") }
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
