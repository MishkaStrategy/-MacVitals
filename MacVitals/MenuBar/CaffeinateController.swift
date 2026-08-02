import Combine
import Foundation

@MainActor
final class CaffeinateController: ObservableObject {
  nonisolated static let executablePath = "/usr/bin/caffeinate"

  @Published private(set) var isActive = false
  @Published private(set) var lastErrorDescription: String?

  private var process: Process?

  nonisolated static func arguments(parentProcessIdentifier: Int32) -> [String] {
    ["-d", "-i", "-w", String(parentProcessIdentifier)]
  }

  func toggle() {
    refreshState()
    if isActive {
      stop()
    } else {
      start()
    }
  }

  func start() {
    refreshState()
    guard process == nil else { return }

    let candidate = Process()
    candidate.executableURL = URL(fileURLWithPath: Self.executablePath)
    candidate.arguments = Self.arguments(
      parentProcessIdentifier: ProcessInfo.processInfo.processIdentifier)
    candidate.standardOutput = FileHandle.nullDevice
    candidate.standardError = FileHandle.nullDevice

    do {
      try candidate.run()
      process = candidate
      isActive = candidate.isRunning
      lastErrorDescription = nil
    } catch {
      process = nil
      isActive = false
      lastErrorDescription = error.localizedDescription
    }
  }

  func stop() {
    process?.terminate()
    process = nil
    isActive = false
    lastErrorDescription = nil
  }

  private func refreshState() {
    guard let process else { return }
    guard !process.isRunning else { return }
    self.process = nil
    isActive = false
  }
}
