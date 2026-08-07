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

  func testEqualScoresUseStableNameAndIDOrdering() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let now = Date(timeIntervalSince1970: 1_800_010_000)
    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    await store.record(
      snapshot: snapshot(
        at: now,
        applications: [
          application(id: "z", name: "Same", cpu: 100),
          application(id: "a", name: "Same", cpu: 100),
          application(id: "middle", name: "Another", cpu: 100),
        ]),
      elapsed: 5)

    let leaders = await store.leaders(metric: .cpu, range: .oneHour, now: now)
    XCTAssertEqual(leaders.map(\.id), ["middle", "a", "z"])
  }

  func testEqualScoreSelectionRetainsStableTopFifteen() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let now = Date(timeIntervalSince1970: 1_800_020_000)
    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    let applications = (0..<16).reversed().map { index in
      application(
        id: String(format: "app-%02d", index),
        name: "Equal",
        cpu: 100,
        memory: 128 * 1_048_576,
        disk: 4_096)
    }
    await store.record(
      snapshot: snapshot(at: now, applications: applications),
      elapsed: 5)

    let leaders = await store.leaders(metric: .cpu, range: .oneHour, now: now)
    XCTAssertEqual(
      leaders.map(\.id),
      (0..<15).map { String(format: "app-%02d", $0) })
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
            disk: 4_096)
        ]),
      elapsed: 5)
    await store.flush()

    let diagnostics = await store.persistenceDiagnostics()
    XCTAssertTrue(diagnostics.segmentedPersistenceReady)
    XCTAssertEqual(diagnostics.segmentFileCount, 1)

    let reloaded = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    let leaders = await reloaded.leaders(metric: .disk, range: .oneHour, now: now)
    XCTAssertEqual(leaders.count, 1)
    XCTAssertEqual(leaders.first?.id, "writer")
    XCTAssertEqual(leaders.first?.diskBytes ?? 0, 20_480, accuracy: 0.0001)
  }

  func testLegacyArchiveMigratesAtomicallyToSegmentedPersistence() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let now = Date(timeIntervalSince1970: 1_800_200_000)
    try writeLegacyArchive(
      to: archiveURL,
      bucketStart: bucketStart(for: now),
      applications: [application(id: "legacy", name: "Legacy", cpu: 80, disk: 2_048)],
      elapsed: 5)

    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    let beforeMigration = await store.leaders(metric: .cpu, range: .oneHour, now: now)
    XCTAssertEqual(beforeMigration.map(\.id), ["legacy"])

    await store.flush()
    let diagnostics = await store.persistenceDiagnostics()
    XCTAssertTrue(diagnostics.segmentedPersistenceReady)
    XCTAssertEqual(diagnostics.segmentFileCount, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))

    let segmentDirectory = HistoricalConsumptionArchiveStore.segmentDirectoryURL(for: archiveURL)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: segmentDirectory.appendingPathComponent("FORMAT.json").path))

    let reloaded = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    let afterMigration = await reloaded.leaders(metric: .disk, range: .oneHour, now: now)
    XCTAssertEqual(afterMigration.map(\.id), ["legacy"])
    XCTAssertEqual(afterMigration.first?.diskBytes ?? 0, 10_240, accuracy: 0.0001)
  }

  func testPartialMigrationWithoutMarkerFallsBackToLegacyArchive() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let now = Date(timeIntervalSince1970: 1_800_300_000)
    try writeLegacyArchive(
      to: archiveURL,
      bucketStart: bucketStart(for: now),
      applications: [application(id: "authoritative", name: "Authoritative", cpu: 90)],
      elapsed: 5)

    let segmentDirectory = HistoricalConsumptionArchiveStore.segmentDirectoryURL(for: archiveURL)
    try FileManager.default.createDirectory(
      at: segmentDirectory,
      withIntermediateDirectories: true)
    try Data("partial-migration".utf8).write(
      to: segmentDirectory.appendingPathComponent("segment-0.json"))

    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    let leaders = await store.leaders(metric: .cpu, range: .oneHour, now: now)
    XCTAssertEqual(leaders.map(\.id), ["authoritative"])

    await store.flush()
    let reloaded = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    let reloadedLeaders = await reloaded.leaders(metric: .cpu, range: .oneHour, now: now)
    XCTAssertEqual(reloadedLeaders.map(\.id), ["authoritative"])
  }

  func testCorruptSegmentIsRejectedWithoutExposingCorruptLeaders() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let now = Date(timeIntervalSince1970: 1_800_400_000)
    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    await store.record(
      snapshot: snapshot(
        at: now,
        applications: [application(id: "valid", name: "Valid", cpu: 100)]),
      elapsed: 5)
    await store.flush()

    let files = try persistedSegmentFiles(for: archiveURL)
    XCTAssertEqual(files.count, 1)
    try Data("not-json".utf8).write(to: try XCTUnwrap(files.first), options: .atomic)

    let reloaded = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    let leaders = await reloaded.leaders(metric: .cpu, range: .oneHour, now: now)
    XCTAssertTrue(leaders.isEmpty)
    XCTAssertNil(await reloaded.firstRecordedAt())
  }

  func testSteadyStateFlushWritesOnlyDirtyHourAndNoOpFlushWritesNothing() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    let firstHour = Date(timeIntervalSince1970: 1_800_500_000)
    let secondHour = firstHour.addingTimeInterval(60 * 60)
    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)

    await store.record(
      snapshot: snapshot(
        at: firstHour,
        applications: [application(id: "first", name: "First", cpu: 20)]),
      elapsed: 5)
    await store.record(
      snapshot: snapshot(
        at: secondHour,
        applications: [application(id: "second", name: "Second", cpu: 30)]),
      elapsed: 5)
    await store.flush()

    let segmentFiles = try persistedSegmentFiles(for: archiveURL)
    XCTAssertEqual(segmentFiles.count, 2)
    let oldestSegment = try XCTUnwrap(segmentFiles.first)
    let oldestSegmentBefore = try Data(contentsOf: oldestSegment)

    await store.resetPersistenceDiagnostics()
    await store.record(
      snapshot: snapshot(
        at: secondHour.addingTimeInterval(10),
        applications: [application(id: "second", name: "Second", cpu: 40)]),
      elapsed: 5)
    await store.flush()

    let dirtyFlush = await store.persistenceDiagnostics()
    XCTAssertEqual(dirtyFlush.fileWriteCount, 1)
    XCTAssertGreaterThan(dirtyFlush.bytesWritten, 0)
    XCTAssertEqual(dirtyFlush.segmentFileCount, 2)
    XCTAssertEqual(try Data(contentsOf: oldestSegment), oldestSegmentBefore)

    await store.resetPersistenceDiagnostics()
    await store.flush()
    let noOpFlush = await store.persistenceDiagnostics()
    XCTAssertEqual(noOpFlush.fileWriteCount, 0)
    XCTAssertEqual(noOpFlush.bytesWritten, 0)
    XCTAssertEqual(noOpFlush.dirtySegmentCount, 0)
  }

  func testFailedSegmentPersistenceRetainsDirtyStateForRetry() async throws {
    let archiveURL = temporaryArchiveURL()
    let root = archiveURL.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let segmentDirectory = HistoricalConsumptionArchiveStore.segmentDirectoryURL(for: archiveURL)
    let symlinkTarget = root.appendingPathComponent("unsafe-target", isDirectory: true)
    try FileManager.default.createDirectory(at: symlinkTarget, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: segmentDirectory,
      withDestinationURL: symlinkTarget)

    let now = Date(timeIntervalSince1970: 1_800_600_000)
    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    await store.record(
      snapshot: snapshot(
        at: now,
        applications: [application(id: "retry", name: "Retry", cpu: 55)]),
      elapsed: 5)

    let failed = await store.persistenceDiagnostics()
    XCTAssertFalse(failed.segmentedPersistenceReady)
    XCTAssertGreaterThan(failed.dirtySegmentCount, 0)

    try FileManager.default.removeItem(at: segmentDirectory)
    await store.flush()

    let recovered = await store.persistenceDiagnostics()
    XCTAssertTrue(recovered.segmentedPersistenceReady)
    XCTAssertEqual(recovered.dirtySegmentCount, 0)
    XCTAssertEqual(recovered.segmentFileCount, 1)

    let reloaded = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    let leaders = await reloaded.leaders(metric: .cpu, range: .oneHour, now: now)
    XCTAssertEqual(leaders.map(\.id), ["retry"])
  }

  func testCorruptArchiveFailsClosed() async throws {
    let archiveURL = temporaryArchiveURL()
    defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

    try FileManager.default.createDirectory(
      at: archiveURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: archiveURL)

    let store = HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    let firstRecordedAt = await store.firstRecordedAt()
    let leaders = await store.leaders(metric: .cpu, range: .sevenDays)
    XCTAssertNil(firstRecordedAt)
    XCTAssertTrue(leaders.isEmpty)
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
    let firstRecordedAt = await store.firstRecordedAt()
    let diagnostics = await store.persistenceDiagnostics()
    XCTAssertEqual(leaders.map(\.id), ["new"])
    XCTAssertEqual(firstRecordedAt, bucketStart(for: currentDate))
    XCTAssertEqual(diagnostics.segmentFileCount, 1)
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

  private func writeLegacyArchive(
    to archiveURL: URL,
    bucketStart: Date,
    applications: [ApplicationProcessUsage],
    elapsed: TimeInterval
  ) throws {
    var aggregates: [String: HistoricalConsumptionAggregate] = [:]
    for application in applications {
      var aggregate = HistoricalConsumptionAggregate(application: application)
      aggregate.add(application: application, elapsed: elapsed)
      aggregates[application.id] = aggregate
    }
    var archive = HistoricalConsumptionArchive()
    archive.buckets = [
      HistoricalConsumptionBucket(startedAt: bucketStart, applications: aggregates)
    ]
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    try FileManager.default.createDirectory(
      at: archiveURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    try encoder.encode(archive).write(to: archiveURL, options: .atomic)
  }

  private func persistedSegmentFiles(for archiveURL: URL) throws -> [URL] {
    let directory = HistoricalConsumptionArchiveStore.segmentDirectoryURL(for: archiveURL)
    return try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles])
      .filter { url in
        guard url.lastPathComponent.hasPrefix("segment-"),
          url.pathExtension == "json",
          let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else {
          return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
      }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
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
