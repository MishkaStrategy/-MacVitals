import AppKit
import Darwin
import Foundation
import XCTest

@testable import MacVitals

@MainActor
final class ProcessWakeupSingleClockValidationTests: XCTestCase {
  func testLegacyIndependentProcessConsumersForWakeupMeasurement() async throws {
    let first = LegacyIndependentProcessConsumersMonitor()
    let second = LegacyIndependentProcessConsumersMonitor()
    try await runMeasurement(
      firstStart: { first.start(interval: 1) },
      firstReady: { first.isReady },
      secondStart: { second.start(interval: 1) },
      secondReady: { second.isReady },
      firstTimestamp: { first.snapshot.timestamp },
      secondTimestamp: { second.snapshot.timestamp },
      stop: {
        first.stop()
        second.stop()
      })
  }

  func testSingleClockProcessConsumersForWakeupMeasurement() async throws {
    let first = ProcessConsumersMonitor()
    let second = ProcessConsumersMonitor()
    try await runMeasurement(
      firstStart: { first.start(interval: 1) },
      firstReady: {
        first.isRunning && first.snapshot.timestamp != .distantPast
          && first.snapshot.sampledProcessCount > 0
      },
      secondStart: { second.start(interval: 1) },
      secondReady: {
        second.isRunning && second.snapshot.timestamp != .distantPast
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
      let readyPath = environment["MACVITALS_WAKEUP_AB_READY_FILE"], !readyPath.isEmpty,
      let completePath = environment["MACVITALS_WAKEUP_AB_COMPLETE_FILE"], !completePath.isEmpty,
      let taskPowerPath = environment["MACVITALS_WAKEUP_AB_TASK_POWER_FILE"], !taskPowerPath.isEmpty
    else {
      throw XCTSkip("Single-clock wakeup A/B evidence paths are required")
    }

    firstStart()
    defer { stop() }
    try await waitUntil(timeout: 20, description: "first process consumer", condition: firstReady)

    secondStart()
    try await waitUntil(timeout: 20, description: "second process consumer", condition: secondReady)

    let firstInitialTimestamp = firstTimestamp()
    let secondInitialTimestamp = secondTimestamp()
    let before = try readTaskPowerInfo()
    let startedAt = Date()

    try Data("two-consumers-active\n".utf8).write(
      to: URL(fileURLWithPath: readyPath),
      options: .atomic)

    try await Task.sleep(for: .seconds(60))
    let elapsed = Date().timeIntervalSince(startedAt)
    let after = try readTaskPowerInfo()
    let taskPower = try TaskPowerWakeupEvidence(before: before, after: after, duration: elapsed)
    let data = try JSONEncoder.sortedPretty.encode(taskPower)
    try data.write(to: URL(fileURLWithPath: taskPowerPath), options: .atomic)

    // External exact-PID proc/rusage + canonical resource collectors begin after the ready marker.
    // Keep the application host alive long enough for those 60-second windows to finish safely.
    try await Task.sleep(for: .seconds(10))

    XCTAssertGreaterThan(firstTimestamp(), firstInitialTimestamp)
    XCTAssertGreaterThan(secondTimestamp(), secondInitialTimestamp)

    try Data("two-consumers-complete\n".utf8).write(
      to: URL(fileURLWithPath: completePath),
      options: .atomic)
  }

  private func readTaskPowerInfo() throws -> TaskPowerSnapshot {
    var info = task_power_info_data_t()
    var count = mach_msg_type_number_t(TASK_POWER_INFO_COUNT)
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
    XCTFail("Timed out waiting for \(description) to become active")
    throw ValidationError.timedOut
  }

  private enum ValidationError: Error {
    case timedOut
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
  let schemaVersion = 1
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

private extension JSONEncoder {
  static var sortedPretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
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
