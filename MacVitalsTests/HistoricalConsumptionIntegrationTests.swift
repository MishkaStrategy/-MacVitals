import Foundation
import XCTest

@testable import MacVitals

final class HistoricalConsumptionIntegrationTests: XCTestCase {
  func testArchiveRanksSupportedMetricsAndRejectsNetworkLeaders() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    await store.record(
      snapshot: snapshot(
        at: now,
        applications: [
          application(id: "fast", name: "Fast", cpu: 220, memory: 512 * 1_048_576),
          application(id: "slow", name: "Slow", cpu: 25, memory: 256 * 1_048_576),
        ]),
      elapsed: 10)

    let cpuLeaders = await store.leaders(metric: .cpu, range: .oneHour, now: now)
    XCTAssertEqual(cpuLeaders.map(\.id), ["fast", "slow"])
    XCTAssertEqual(cpuLeaders.first?.cpuCoreSeconds ?? 0, 22, accuracy: 0.0001)

    let networkLeaders = await store.leaders(metric: .network, range: .oneHour, now: now)
    XCTAssertTrue(networkLeaders.isEmpty)
  }

  func testArchivePersistsAndReloadsDeterministically() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let now = Date(timeIntervalSince1970: 1_800_100_000)
    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    await store.record(
      snapshot: snapshot(
        at: now,
        applications: [
          application(
            id: "writer",
            name: "Writer",
            cpu: 10,
            memory: 128 * 1_048_576,
            disk: 4_096),
        ]),
      elapsed: 5)
    await store.flush()

    let reloaded = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    let leaders = await reloaded.leaders(metric: .disk, range: .oneHour, now: now)
    XCTAssertEqual(leaders.count, 1)
    XCTAssertEqual(leaders.first?.id, "writer")
    XCTAssertEqual(leaders.first?.diskBytes ?? 0, 20_480, accuracy: 0.0001)
  }

  func testCorruptArchiveFailsClosed() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    try FileManager.default.createDirectory(
      at: archiveURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: archiveURL)

    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    XCTAssertNil(await store.firstRecordedAt())
    XCTAssertTrue(await store.leaders(metric: .cpu, range: .sevenDays).isEmpty)
  }

  func testArchivePrunesDataOutsideRetentionWindow() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
    let currentDate = oldDate.addingTimeInterval(8 * 24 * 60 * 60)

    await store.record(
      snapshot: snapshot(
        at: oldDate,
        applications: [application(id: "old", name: "Old", cpu: 100)]),
      elapsed: 5)
    await store.record(
      snapshot: snapshot(
        at: currentDate,
        applications: [application(id: "new", name: "New", cpu: 100)]),
      elapsed: 5)

    let leaders = await store.leaders(metric: .cpu, range: .sevenDays, now: currentDate)
    XCTAssertEqual(leaders.map(\.id), ["new"])
    XCTAssertEqual(await store.firstRecordedAt(), bucketStart(for: currentDate))
  }

  func testSupplementalFormattersClampInvalidValues() {
    XCTAssertEqual(StorageByteFormatter.percentage(-1), "0%")
    XCTAssertEqual(StorageByteFormatter.percentage(2), "100%")
    XCTAssertEqual(StorageByteFormatter.percentage(.nan), "—")
    XCTAssertEqual(NetworkByteFormatter.rate(nil), L10n.string("Collecting data"))
    XCTAssertTrue(NetworkByteFormatter.rate(1_024).hasSuffix("/s"))
  }

  private func temporaryArchiveURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("MacVitalsTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("consumption-history.json", isDirectory: false)
  }

  private func snapshot(
    at timestamp: Date,
    applications: [ApplicationProcessUsage]
  ) -> ProcessMetricsSnapshot {
    ProcessMetricsSnapshot(
      timestamp: timestamp,
      applications: applications,
      sampledProcessCount: applications.count,
      energyCountersAvailable: applications.contains { $0.energyWatts != nil })
  }

  private func application(
    id: String,
    name: String,
    cpu: Double,
    memory: UInt64 = 64 * 1_048_576,
    disk: Double = 0
  ) -> ApplicationProcessUsage {
    ApplicationProcessUsage(
      id: id,
      name: name,
      bundleIdentifier: "test.\(id)",
      representativePID: 100,
      processCount: 1,
      cpuPercent: cpu,
      memoryBytes: memory,
      energyWatts: nil,
      energyImpactScore: cpu / 2,
      gpuActivityScore: cpu / 3,
      diskBytesPerSecond: disk,
      isGPUActivityEstimated: true,
      isEnergyEstimated: true)
  }

  private func bucketStart(for date: Date) -> Date {
    let duration: TimeInterval = 5 * 60
    return Date(
      timeIntervalSince1970:
        floor(date.timeIntervalSince1970 / duration) * duration)
  }
}
