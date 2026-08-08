import AppKit
import Darwin
import Foundation
import XCTest

@testable import MacVitals

@MainActor
final class ProcessWakeupMatchedControlTests: XCTestCase {
  func testNoProcessConsumerControlWindow() async throws {
    try await runMeasurement(
      prepare: {},
      ready: { true },
      verify: {},
      stop: {})
  }

  func testLegacyIndependentProcessConsumersWindow() async throws {
    let first = LegacyIndependentProcessConsumersMonitor()
    let second = LegacyIndependentProcessConsumersMonitor()
    var firstInitialTimestamp = Date.distantPast
    var secondInitialTimestamp = Date.distantPast

    try await runMeasurement(
      prepare: {
        first.start(interval: 1)
        try await self.waitUntil(timeout: 20, description: "first legacy consumer") {
          first.isReady
        }
        second.start(interval: 1)
        try await self.waitUntil(timeout: 20, description: "second legacy consumer") {
          second.isReady
        }
        firstInitialTimestamp = first.snapshot.timestamp
        secondInitialTimestamp = second.snapshot.timestamp
      },
      ready: { first.isReady && second.isReady },
      verify: {
        XCTAssertGreaterThan(first.snapshot.timestamp, firstInitialTimestamp)
        XCTAssertGreaterThan(second.snapshot.timestamp, secondInitialTimestamp)
      },
      stop: {
        first.stop()
        second.stop()
      })
  }

  func testSingleClockProcessConsumersWindow() async throws {
    let first = ProcessConsumersMonitor()
    let second = ProcessConsumersMonitor()
    var firstInitialTimestamp = Date.distantPast
    var secondInitialTimestamp = Date.distantPast

    try await runMeasurement(
      prepare: {
        first.start(interval: 1)
        try await self.waitUntil(timeout: 20, description: "first single-clock consumer") {
          first.isRunning && first.snapshot.timestamp != .distantPast
            && first.snapshot.sampledProcessCount > 0
        }
        second.start(interval: 1)
        try await self.waitUntil(timeout: 20, description: "second single-clock consumer") {
          second.isRunning && second.snapshot.timestamp != .distantPast
            && second.snapshot.sampledProcessCount > 0
        }
        firstInitialTimestamp = first.snapshot.timestamp
        secondInitialTimestamp = second.snapshot.timestamp
      },
      ready: {
        first.isRunning && second.isRunning
          && first.snapshot.sampledProcessCount > 0
          && second.snapshot.sampledProcessCount > 0
      },
      verify: {
        XCTAssertGreaterThan(first.snapshot.timestamp, firstInitialTimestamp)
        XCTAssertGreaterThan(second.snapshot.timestamp, secondInitialTimestamp)
      },
      stop: {
        first.stop()
        second.stop()
      })
  }

  private func runMeasurement(
    prepare: @escaping @MainActor () async throws -> Void,
    ready: @escaping @MainActor () -> Bool,
    verify: @escaping @MainActor () -> Void,
    stop: @escaping @MainActor () -> Void
  ) async throws {
    let environment = ProcessInfo.processInfo.environment
    guard
      let readyPath = environment["MACVITALS_WAKEUP_CONTROL_READY_FILE"], !readyPath.isEmpty,
      let completePath = environment["MACVITALS_WAKEUP_CONTROL_COMPLETE_FILE"], !completePath.isEmpty,
      let taskPowerPath = environment["MACVITALS_WAKEUP_CONTROL_TASK_POWER_FILE"], !taskPowerPath.isEmpty
    else {
      throw XCTSkip("Matched-control wakeup evidence paths are required")
    }

    try await prepare()
    defer { stop() }
    guard ready() else {
      XCTFail("Matched-control scenario did not reach its required steady state")
      throw ValidationError.notReady
    }

    // Use the same warm-settle delay in control, legacy and product scenarios.
    try await Task.sleep(for: .seconds(2))

    let before = try readTaskPowerInfo()
    let startedAt = Date()
    try Data("measurement-ready\n".utf8).write(
      to: URL(fileURLWithPath: readyPath),
      options: .atomic)

    try await Task.sleep(for: .seconds(60))

    let elapsed = Date().timeIntervalSince(startedAt)
    let after = try readTaskPowerInfo()
    let taskPower = try TaskPowerWakeupEvidence(before: before, after: after, duration: elapsed)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(taskPower).write(
      to: URL(fileURLWithPath: taskPowerPath),
      options: .atomic)

    // Keep the exact process alive until the external 60-second collectors have drained.
    try await Task.sleep(for: .seconds(10))
    verify()

    try Data("measurement-complete\n".utf8).write(
      to: URL(fileURLWithPath: completePath),
      options: .atomic)
  }

  private func readTaskPowerInfo() throws -> TaskPowerSnapshot {
    var info = task_power_info_data_t()
    let integerCount = MemoryLayout<task_power_info_data_t>.size / MemoryLayout<integer_t>.size
    var count = mach_msg_type_number_t(integerCount)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), rebound, &count)
      }
    }
    guard result == KERN_SUCCESS else {
      XCTFail("TASK_POWER_INFO failed with kern_return_t=\(result)")
      throw ValidationError.taskPowerInfoFailed(result)
    }
    return TaskPowerSnapshot(
      interruptWakeups: info.task_interrupt_wakeups,
      platformIdleWakeups: info.task_platform_idle_wakeups,
      timerWakeupsBin1: info.task_timer_wakeups_bin_1,
      timerWakeupsBin2: info.task_timer_wakeups_bin_2)
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
    XCTFail("Timed out waiting for \(description)")
    throw ValidationError.timedOut
  }

  private enum ValidationError: Error {
    case timedOut
    case notReady
    case taskPowerInfoFailed(kern_return_t)
  }
}

private struct TaskPowerSnapshot {
  let interruptWakeups: UInt64
  let platformIdleWakeups: UInt64
  let timerWakeupsBin1: UInt64
  let timerWakeupsBin2: UInt64
}

private struct TaskPowerWakeupEvidence: Codable {
  let schemaVersion: Int
  let durationSeconds: Double
  let interruptWakeupsDelta: UInt64
  let platformIdleWakeupsDelta: UInt64
  let timerWakeupsBin1Delta: UInt64
  let timerWakeupsBin2Delta: UInt64
  let interruptWakeupsPerSecond: Double
  let platformIdleWakeupsPerSecond: Double
  let timerWakeupsBin1PerSecond: Double
  let timerWakeupsBin2PerSecond: Double
  let totalTimerWakeupsPerSecond: Double

  init(before: TaskPowerSnapshot, after: TaskPowerSnapshot, duration: TimeInterval) throws {
    guard duration.isFinite, duration >= 59 else { throw EvidenceError.invalidDuration }
    let interrupt = try Self.delta(before.interruptWakeups, after.interruptWakeups)
    let platformIdle = try Self.delta(before.platformIdleWakeups, after.platformIdleWakeups)
    let bin1 = try Self.delta(before.timerWakeupsBin1, after.timerWakeupsBin1)
    let bin2 = try Self.delta(before.timerWakeupsBin2, after.timerWakeupsBin2)

    schemaVersion = 1
    durationSeconds = duration
    interruptWakeupsDelta = interrupt
    platformIdleWakeupsDelta = platformIdle
    timerWakeupsBin1Delta = bin1
    timerWakeupsBin2Delta = bin2
    interruptWakeupsPerSecond = Double(interrupt) / duration
    platformIdleWakeupsPerSecond = Double(platformIdle) / duration
    timerWakeupsBin1PerSecond = Double(bin1) / duration
    timerWakeupsBin2PerSecond = Double(bin2) / duration
    totalTimerWakeupsPerSecond = Double(bin1 + bin2) / duration
  }

  private static func delta(_ before: UInt64, _ after: UInt64) throws -> UInt64 {
    guard after >= before else { throw EvidenceError.counterMovedBackward }
    return after - before
  }

  private enum EvidenceError: Error {
    case invalidDuration
    case counterMovedBackward
  }
}

@MainActor
private final class LegacyIndependentProcessConsumersMonitor {
  private(set) var snapshot: ProcessMetricsSnapshot = .empty
  private(set) var isRunning = false

  var isReady: Bool {
    isRunning && snapshot.timestamp != .distantPast && snapshot.sampledProcessCount > 0
  }

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
      guard !application.isTerminated,
        application.processIdentifier > 0
      else {
        return nil
      }
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
