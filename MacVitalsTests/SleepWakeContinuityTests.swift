import Foundation
import XCTest

@testable import MacVitals

final class SleepWakeContinuityTests: XCTestCase {
  func testHistoricalContinuousRecordingSkipsLongSamplingGap() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    await store.recordContinuous(
      snapshot: snapshot(at: now),
      elapsed: HistoricalConsumptionContinuityPolicy.maximumContinuousElapsed + 1)

    let leaders = await store.leaders(metric: .cpu, range: .oneHour, now: now)
    let firstRecordedAt = await store.firstRecordedAt()
    let diagnostics = await store.persistenceDiagnostics()

    XCTAssertTrue(leaders.isEmpty)
    XCTAssertNil(firstRecordedAt)
    XCTAssertEqual(diagnostics.fileWriteCount, 0)
    XCTAssertEqual(diagnostics.dirtySegmentCount, 0)
  }

  func testHistoricalContinuousRecordingAcceptsMaximumSamplingGap() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let now = Date(timeIntervalSince1970: 1_900_000_100)
    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    await store.recordContinuous(
      snapshot: snapshot(at: now),
      elapsed: HistoricalConsumptionContinuityPolicy.maximumContinuousElapsed)

    let leaders = await store.leaders(metric: .cpu, range: .oneHour, now: now)
    XCTAssertEqual(leaders.map(\.id), ["continuity-test"])
    XCTAssertEqual(leaders.first?.cpuCoreSeconds ?? 0, 60, accuracy: 0.0001)
  }

  func testHistoricalContinuityPolicyRejectsInvalidOrTooShortElapsed() {
    XCTAssertNil(HistoricalConsumptionContinuityPolicy.recordingElapsed(.nan))
    XCTAssertNil(HistoricalConsumptionContinuityPolicy.recordingElapsed(.infinity))
    XCTAssertNil(HistoricalConsumptionContinuityPolicy.recordingElapsed(0.25))
    XCTAssertNil(HistoricalConsumptionContinuityPolicy.recordingElapsed(-1))
    XCTAssertEqual(
      HistoricalConsumptionContinuityPolicy.recordingElapsed(0.251) ?? -1,
      0.251,
      accuracy: 0.000_001)
  }

  private func snapshot(at timestamp: Date) -> ProcessMetricsSnapshot {
    ProcessMetricsSnapshot(
      timestamp: timestamp,
      applications: [historicalApplication()],
      sampledProcessCount: 1,
      energyCountersAvailable: false)
  }

  private func historicalApplication() -> ApplicationProcessUsage {
    ApplicationProcessUsage(
      id: "continuity-test",
      name: "Continuity Test",
      bundleIdentifier: "test.continuity",
      representativePID: 42,
      processCount: 1,
      cpuPercent: 100,
      memoryBytes: 128 * 1_048_576,
      energyWatts: nil,
      energyImpactScore: 50,
      gpuActivityScore: 25,
      diskBytesPerSecond: 4_096,
      isGPUActivityEstimated: true,
      isEnergyEstimated: true)
  }

  private func temporaryArchiveURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("MacVitalsSleepWakeTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("consumption-history.json", isDirectory: false)
  }
}
