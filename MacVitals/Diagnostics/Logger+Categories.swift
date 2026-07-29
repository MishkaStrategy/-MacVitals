import Foundation
import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mishkacher.MacVitals"
    static let lifecycle = Logger(subsystem: subsystem, category: "app-lifecycle")
    static let metrics = Logger(subsystem: subsystem, category: "metrics")
    static let providers = Logger(subsystem: subsystem, category: "providers")
    static let power = Logger(subsystem: subsystem, category: "power")
    static let menuBar = Logger(subsystem: subsystem, category: "menu-bar")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
    static let release = Logger(subsystem: subsystem, category: "release")
}
