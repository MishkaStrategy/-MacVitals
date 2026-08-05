import Combine
import Foundation

@MainActor
final class CaffeinateController: ObservableObject {
  nonisolated static let executablePath = "/usr/bin/caffeinate"

  @Published private(set) var isActive = false
  @Published private(set) var lastErrorDescription: String?

  private let executableURL: URL
  private let argumentsProvider: (Int32) -> [String]
  private let processIdentifierProvider: () -> Int32
  private var process: Process?
  private var activeProcessID: UUID?

  init(
    executablePath: String = CaffeinateController.executablePath,
    argumentsProvider: @escaping (Int32) -> [String] = CaffeinateController.arguments,
    processIdentifierProvider: @escaping () -> Int32 = {
      ProcessInfo.processInfo.processIdentifier
    }
  ) {
    executableURL = URL(fileURLWithPath: executablePath)
    self.argumentsProvider = argumentsProvider
    self.processIdentifierProvider = processIdentifierProvider
  }

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
    let processID = UUID()
    candidate.executableURL = executableURL
    candidate.arguments = argumentsProvider(processIdentifierProvider())
    candidate.standardOutput = FileHandle.nullDevice
    candidate.standardError = FileHandle.nullDevice
    candidate.terminationHandler = { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handleTermination(processID: processID)
      }
    }

    do {
      try candidate.run()
      process = candidate
      activeProcessID = processID
      isActive = candidate.isRunning
      lastErrorDescription = nil
      if !candidate.isRunning {
        handleTermination(processID: processID)
      }
    } catch {
      candidate.terminationHandler = nil
      process = nil
      activeProcessID = nil
      isActive = false
      lastErrorDescription = error.localizedDescription
    }
  }

  func stop() {
    let candidate = process
    process = nil
    activeProcessID = nil
    candidate?.terminationHandler = nil
    if candidate?.isRunning == true {
      candidate?.terminate()
    }
    isActive = false
    lastErrorDescription = nil
  }

  private func refreshState() {
    guard let process else { return }
    guard !process.isRunning else { return }
    process.terminationHandler = nil
    self.process = nil
    activeProcessID = nil
    isActive = false
  }

  private func handleTermination(processID: UUID) {
    guard activeProcessID == processID else { return }
    process?.terminationHandler = nil
    process = nil
    activeProcessID = nil
    isActive = false
  }
}
