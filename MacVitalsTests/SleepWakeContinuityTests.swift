import Foundation
import XCTest

@testable import MacVitals

final class SleepWakeContinuityTests: XCTestCase {
  func testProcessCounterDeltaRejectsLongSamplingGap() {
    let previous = processSample(
      cpu: 1_000_000_000,
      energy: 2_000_000_000,
      read: 100,
      write: 200)
    let current = processSample(
      cpu: 2_000_000_000,
      energy: 3_000_000_000,
      read: 1_100,
      write: 1_200)

    let delta = ProcessCounterCalculator.delta(
      previous: previous,
      current: current,
      elapsedSeconds: 61)

    XCTAssertEqual(delta.cpuPercent, 0)
    XCTAssertNil(delta.energyWatts)
    XCTAssertEqual(delta.diskBytesPerSecond, 0)
  }

  func testHistoricalArchiveSkipsLongSamplingGap() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    await store.record(
      snapshot: ProcessMetricsSnapshot(
        timestamp: now,
        applications: [historicalApplication()],
        sampledProcessCount: 1,
        energyCountersAvailable: false),
      elapsed: 61)

    let leaders = await store.leaders(metric: .cpu, range: .oneHour, now: now)
    let firstRecordedAt = await store.firstRecordedAt()
    let diagnostics = await store.persistenceDiagnostics()

    XCTAssertTrue(leaders.isEmpty)
    XCTAssertNil(firstRecordedAt)
    XCTAssertEqual(diagnostics.fileWriteCount, 0)
    XCTAssertEqual(diagnostics.dirtySegmentCount, 0)
  }

  private func processSample(
    cpu: UInt64,
    energy: UInt64?,
    read: UInt64?,
    write: UInt64?
  ) -> ProcessCounterSample {
    ProcessCounterSample(
      pid: 42,
      parentPID: 1,
      startTime: 1,
      name: "Continuity Test",
      cpuTimeNanoseconds: cpu,
      physicalFootprintBytes: 128 * 1_048_576,
      energyNanojoules: energy,
      diskReadBytes: read,
      diskWriteBytes: write)
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
