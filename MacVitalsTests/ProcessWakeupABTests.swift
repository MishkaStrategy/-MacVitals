import AppKit
import Foundation
import XCTest

@testable import MacVitals

@MainActor
final class ProcessWakeupABTests: XCTestCase {
  func testLegacyIndependentProcessConsumersForWakeupMeasurement() async throws {
    let first = LegacyIndependentProcessConsumersMonitor()
    let second = LegacyIndependentProcessConsumersMonitor()
    try await runMeasurement(
      firstStart: { first.start(interval: 1) },
      firstReady: {
        first.isRunning
          && first.snapshot.timestamp != .distantPast
          && first.snapshot.sampledProcessCount > 0
      },
      secondStart: { second.start(interval: 1) },
      secondReady: {
        second.isRunning
          && second.snapshot.timestamp != .distantPast
          && second.snapshot.sampledProcessCount > 0
      },
      firstTimestamp: { first.snapshot.timestamp },
      secondTimestamp: { second.snapshot.timestamp },
      stop: {
        first.stop()
        second.stop()
      })
  }

  func testSharedProcessConsumersForWakeupMeasurement() async throws {
    let first = ProcessConsumersMonitor()
    let second = ProcessConsumersMonitor()
    try await runMeasurement(
      firstStart: { first.start(interval: 1) },
      firstReady: {
        first.isRunning
          && first.snapshot.timestamp != .distantPast
          && first.snapshot.sampledProcessCount > 0
      },
      secondStart: { second.start(interval: 1) },
      secondReady: {
        second.isRunning
          && second.snapshot.timestamp != .distantPast
          && second.snapshot.sampledProcessCount > 0
      },
      firstTimestamp: { first.snapshot.timestamp },
      secondTimestamp: { second.snapshot.timestamp },
      stop: {
        first.stop()
        second.stop()
      })
  }

  private func runMeasurement(
    firstStart: () -> Void,
    firstReady: @escaping @MainActor () -> Bool,
    secondStart: () -> Void,
    secondReady: @escaping @MainActor () -> Bool,
    firstTimestamp: @escaping @MainActor () -> Date,
    secondTimestamp: @escaping @MainActor () -> Date,
    stop: () -> Void
  ) async throws {
    let environment = ProcessInfo.processInfo.environment
    guard
      let readyPath = environment["MACVITALS_WAKEUP_AB_READY_FILE"],
      !readyPath.isEmpty,
      let completePath = environment["MACVITALS_WAKEUP_AB_COMPLETE_FILE"],
      !completePath.isEmpty
    else {
      throw XCTSkip("Wakeup A/B markers are required")
    }

    firstStart()
    defer { stop() }
    try await waitUntil(timeout: 20, description: "first process consumer", condition: firstReady)

    secondStart()
    try await waitUntil(timeout: 20, description: "second process consumer", condition: secondReady)

    let firstInitialTimestamp = firstTimestamp()
    let secondInitialTimestamp = secondTimestamp()
    try Data("two-consumers-active\n".utf8).write(
      to: URL(fileURLWithPath: readyPath),
      options: .atomic)

    try await Task.sleep(for: .seconds(70))

    XCTAssertGreaterThan(firstTimestamp(), firstInitialTimestamp)
    XCTAssertGreaterThan(secondTimestamp(), secondInitialTimestamp)

    try Data("two-consumers-complete\n".utf8).write(
      to: URL(fileURLWithPath: completePath),
      options: .atomic)
  }

  private func waitUntil(
    timeout: TimeInterval,
    description: String,
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTFail("Timed out waiting for \(description) to become active")
    throw ValidationError.timedOut
  }

  private enum ValidationError: Error {
    case timedOut
  }
}

/// Validation-only reproduction of the exact pre-centralization ownership model from
/// PR #71 base c10831e3717ca0bbf50ca0a8f784c8cca3da5411. It intentionally uses the current
/// ProcessMetricsProvider implementation so the A/B changes only provider ownership/coalescing,
/// not later provider correctness or allocation fixes.
@MainActor
private final class LegacyIndependentProcessConsumersMonitor {
  private(set) var snapshot: ProcessMetricsSnapshot = .empty
  private(set) var isRunning = false

  private let provider = ProcessMetricsProvider()
  private var task: Task<Void, Never>?

  func start(interval: TimeInterval) {
    guard task == nil else { return }
    isRunning = true
    let refreshInterval = min(30, max(1, interval))
    let provider = self.provider
    task = Task { [weak self, provider] in
      await provider.reset()
      while !Task.isCancelled {
        guard let self else { break }
        let applications = self.runningApplicationDescriptors()
        let next = await provider.sample(runningApplications: applications)
        guard !Task.isCancelled else { break }
        self.snapshot = next
        try? await Task.sleep(for: .seconds(refreshInterval))
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
    isRunning = false
  }

  deinit {
    task?.cancel()
  }

  private func runningApplicationDescriptors() -> [RunningApplicationDescriptor] {
    NSWorkspace.shared.runningApplications.compactMap { application in
      guard !application.isTerminated, application.processIdentifier > 0 else { return nil }
      let name = application.localizedName
        ?? application.bundleIdentifier
        ?? L10n.string("Unknown process")
      return RunningApplicationDescriptor(
        pid: application.processIdentifier,
        name: name,
        bundleIdentifier: application.bundleIdentifier)
    }
  }
}
