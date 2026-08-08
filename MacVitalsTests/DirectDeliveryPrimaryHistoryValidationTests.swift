import Foundation
import XCTest

@testable import MacVitals

@MainActor
final class DirectDeliveryPrimaryHistoryValidationTests: XCTestCase {
  func testLivePrimaryAndHistoryAdvanceThroughDirectDelivery() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard
      let readyPath = environment["MACVITALS_DIRECT_DELIVERY_HISTORY_READY_FILE"], !readyPath.isEmpty,
      let completePath = environment["MACVITALS_DIRECT_DELIVERY_HISTORY_COMPLETE_FILE"], !completePath.isEmpty
    else {
      throw XCTSkip("Direct-delivery primary/history evidence paths are required")
    }

    let monitor = ProcessConsumersMonitor()
    let history = HistoricalConsumptionCenter.shared
    let historyWasCollecting = history.isCollecting

    history.stop(flush: false)
    monitor.start(interval: 1)
    history.start(interval: 1, initialDelay: 0)

    defer {
      monitor.stop()
      history.stop(flush: false)
      if historyWasCollecting {
        history.start(interval: 1, initialDelay: 0)
      }
    }

    try await waitUntil(timeout: 20) {
      monitor.isRunning
        && history.isCollecting
        && monitor.snapshot.timestamp != .distantPast
        && monitor.snapshot.sampledProcessCount > 0
    }

    let initialRevision = history.revision
    try await waitUntil(timeout: 20) { history.revision > initialRevision }

    let liveIDs = Set(monitor.snapshot.applications.map(\.id))
    let leaders = await history.leaders(metric: .memory, range: .oneHour)
    XCTAssertFalse(liveIDs.isEmpty, "Live process snapshot must contain applications")
    XCTAssertFalse(leaders.isEmpty, "Historical memory leaders must be available")
    XCTAssertFalse(
      liveIDs.isDisjoint(with: Set(leaders.map(\.id))),
      "Historical leaders must overlap the live process-sampling population")

    let readyRevision = history.revision
    let readySnapshotTimestamp = monitor.snapshot.timestamp
    try Data("primary-and-history-active\n".utf8).write(
      to: URL(fileURLWithPath: readyPath),
      options: .atomic)

    try await Task.sleep(for: .seconds(70))

    let revisionAdvance = history.revision - readyRevision
    let liveAdvance = monitor.snapshot.timestamp.timeIntervalSince(readySnapshotTimestamp)
    XCTAssertGreaterThanOrEqual(
      revisionAdvance,
      30,
      "Autonomous history must keep advancing while the live primary consumer is active")
    XCTAssertGreaterThanOrEqual(
      liveAdvance,
      55,
      "The direct-delivery primary consumer must continue receiving fresh shared snapshots")
    XCTAssertGreaterThan(monitor.snapshot.sampledProcessCount, 0)

    let finalLeaders = await history.leaders(metric: .memory, range: .oneHour)
    XCTAssertFalse(finalLeaders.isEmpty)
    XCTAssertFalse(
      Set(monitor.snapshot.applications.map(\.id)).isDisjoint(with: Set(finalLeaders.map(\.id))))

    try Data("history-and-live-primary-advanced-through-direct-delivery\n".utf8).write(
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
    XCTFail("Timed out waiting for direct-delivery primary/history runtime state")
    throw ValidationError.timedOut
  }

  private enum ValidationError: Error {
    case timedOut
  }
}
