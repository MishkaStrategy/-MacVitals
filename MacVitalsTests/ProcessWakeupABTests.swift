import Foundation
import XCTest

@testable import MacVitals

@MainActor
final class ProcessWakeupABTests: XCTestCase {
  func testTwoConcurrentProcessConsumersForWakeupMeasurement() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard
      let readyPath = environment["MACVITALS_WAKEUP_AB_READY_FILE"],
      !readyPath.isEmpty,
      let completePath = environment["MACVITALS_WAKEUP_AB_COMPLETE_FILE"],
      !completePath.isEmpty
    else {
      throw XCTSkip("Wakeup A/B markers are required")
    }

    let first = ProcessConsumersMonitor()
    let second = ProcessConsumersMonitor()
    first.start(interval: 1)
    second.start(interval: 1)
    defer {
      first.stop()
      second.stop()
    }

    try await waitUntil(timeout: 20) {
      first.isRunning && second.isRunning
        && first.snapshot.timestamp != .distantPast
        && second.snapshot.timestamp != .distantPast
        && first.snapshot.sampledProcessCount > 0
        && second.snapshot.sampledProcessCount > 0
    }

    let firstInitialTimestamp = first.snapshot.timestamp
    let secondInitialTimestamp = second.snapshot.timestamp
    try Data("two-consumers-active\n".utf8).write(
      to: URL(fileURLWithPath: readyPath),
      options: .atomic)

    try await Task.sleep(for: .seconds(70))

    XCTAssertGreaterThan(first.snapshot.timestamp, firstInitialTimestamp)
    XCTAssertGreaterThan(second.snapshot.timestamp, secondInitialTimestamp)
    XCTAssertGreaterThan(first.snapshot.sampledProcessCount, 0)
    XCTAssertGreaterThan(second.snapshot.sampledProcessCount, 0)

    try Data("two-consumers-complete\n".utf8).write(
      to: URL(fileURLWithPath: completePath),
      options: .atomic)
  }

  private func waitUntil(
    timeout: TimeInterval,
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTFail("Timed out waiting for two process consumers to become active")
    throw ValidationError.timedOut
  }

  private enum ValidationError: Error {
    case timedOut
  }
}
