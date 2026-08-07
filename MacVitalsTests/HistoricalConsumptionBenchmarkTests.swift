import Darwin
import Foundation
import XCTest

@testable import MacVitals

final class HistoricalConsumptionBenchmarkTests: XCTestCase {
  func testMatureSevenDayArchiveBaseline() async throws {
    let config = try configuration()
    let outputURL = URL(fileURLWithPath: config.outputPath)
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MacVitalsHistoryBenchmark-\(UUID().uuidString)", isDirectory: true)
    let archiveURL = root.appendingPathComponent("consumption-history-v1.json")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let calibration = try calibratePeakRSS()
    var peakCheckpoints: [UInt64] = [try peakRSSBytes(calibration)]
    let bucketDuration: TimeInterval = 300
    let bucketCount = Int(HistoricalConsumptionRange.sevenDays.duration / bucketDuration)
    let applicationsPerBucket = 24
    let currentBucketStart = floor(1_900_000_000 / bucketDuration) * bucketDuration
    let firstBucketStart = currentBucketStart - Double(bucketCount - 1) * bucketDuration

    let seed = try writeLegacyFixture(
      to: archiveURL,
      bucketDuration: bucketDuration,
      bucketCount: bucketCount,
      applicationsPerBucket: applicationsPerBucket,
      firstBucketStart: firstBucketStart)
    peakCheckpoints.append(try peakRSSBytes(calibration))

    let legacyLoad = measureSync { HistoricalConsumptionArchiveStore(archiveURL: archiveURL) }
    let store = legacyLoad.value
    peakCheckpoints.append(try peakRSSBytes(calibration))
    let now = Date(timeIntervalSince1970: currentBucketStart + 1)
    let sampled = (0..<120).map { application(index: $0, phase: 10_000) }

    let migration = await measureAsync {
      await store.record(snapshot: self.snapshot(at: now, applications: sampled), elapsed: 1)
    }
    let migrationIO = await store.persistenceDiagnostics()
    XCTAssertTrue(migrationIO.segmentedPersistenceReady)
    XCTAssertGreaterThan(migrationIO.segmentFileCount, 100)
    XCTAssertEqual(migrationIO.fileWriteCount, migrationIO.segmentFileCount + 1)
    peakCheckpoints.append(try peakRSSBytes(calibration))

    await store.resetPersistenceDiagnostics()
    var recordDurations: [Double] = []
    for index in 0..<120 {
      let timestamp = now.addingTimeInterval(2 + Double(index) * 0.4)
      let measurement = await measureAsync {
        await store.record(snapshot: self.snapshot(at: timestamp, applications: sampled), elapsed: 0.4)
      }
      recordDurations.append(measurement.milliseconds)
    }
    peakCheckpoints.append(try peakRSSBytes(calibration))

    var flushDurations: [Double] = []
    for index in 0..<3 {
      if index > 0 {
        await store.record(
          snapshot: snapshot(
            at: now.addingTimeInterval(50 + Double(index) * 0.5),
            applications: sampled),
          elapsed: 0.5)
      }
      flushDurations.append((await measureAsync { await store.flush() }).milliseconds)
    }
    let steadyIO = await store.persistenceDiagnostics()
    XCTAssertEqual(steadyIO.fileWriteCount, 3)
    XCTAssertGreaterThan(steadyIO.bytesWritten, 0)
    XCTAssertEqual(steadyIO.dirtySegmentCount, 0)

    await store.resetPersistenceDiagnostics()
    let noOp = await measureAsync { await store.flush() }
    let noOpIO = await store.persistenceDiagnostics()
    XCTAssertEqual(noOpIO.fileWriteCount, 0)
    XCTAssertEqual(noOpIO.bytesWritten, 0)

    let segmentedLoad = measureSync { HistoricalConsumptionArchiveStore(archiveURL: archiveURL) }
    let reloaded = segmentedLoad.value
    let reloadIO = await reloaded.persistenceDiagnostics()
    XCTAssertTrue(reloadIO.segmentedPersistenceReady)
    XCTAssertEqual(reloadIO.segmentFileCount, steadyIO.segmentFileCount)

    let metrics: [HistoricalConsumptionMetric] = [.cpu, .memory, .gpu, .energy, .disk, .thermal]
    var queryResults: [String: Any] = [:]
    for range in HistoricalConsumptionRange.allCases {
      for metric in metrics {
        var durations: [Double] = []
        var expectedIDs: [String]?
        for _ in 0..<5 {
          let measured = await measureAsync {
            await reloaded.leaders(metric: metric, range: range, now: now)
          }
          let ids = measured.value.map(\.id)
          XCTAssertFalse(ids.isEmpty)
          if let expectedIDs { XCTAssertEqual(ids, expectedIDs) } else { expectedIDs = ids }
          durations.append(measured.milliseconds)
        }
        queryResults["\(range.rawValue).\(metric.rawValue)"] = [
          "leaders": expectedIDs?.count ?? 0,
          "p50Milliseconds": percentile(durations, 0.50),
          "p95Milliseconds": percentile(durations, 0.95),
          "maxMilliseconds": durations.max() ?? 0,
        ]
      }
    }
    let network = await measureAsync {
      await reloaded.leaders(metric: .network, range: .sevenDays, now: now)
    }
    XCTAssertTrue(network.value.isEmpty)
    peakCheckpoints.append(try peakRSSBytes(calibration))

    XCTAssertEqual(peakCheckpoints, peakCheckpoints.sorted())
    let segmentedBytes = try directoryBytes(
      HistoricalConsumptionArchiveStore.segmentDirectoryURL(for: archiveURL))
    let averageWriteBytes = Double(steadyIO.bytesWritten) / Double(max(1, steadyIO.fileWriteCount))

    let report: [String: Any] = [
      "schemaVersion": 4,
      "identity": ["productBaseSHA": config.productBaseSHA, "benchmarkSHA": config.benchmarkSHA],
      "fixture": [
        "bucketCount": bucketCount,
        "applicationsPerBucket": applicationsPerBucket,
        "aggregateCount": bucketCount * applicationsPerBucket,
        "seededLegacyArchiveBytes": seed.bytes,
        "segmentedArchiveBytes": segmentedBytes,
        "segmentFileCount": steadyIO.segmentFileCount,
      ],
      "memory": [
        "semantics": "processLifetimePeakRSS",
        "unit": "bytes",
        "ruMaxRSSRawAtCalibration": calibration.raw,
        "currentResidentKiBAtCalibration": calibration.currentKiB,
        "ruMaxRSSScaleToBytes": calibration.scale,
        "systemPhysicalMemoryBytes": calibration.physicalMemory,
        "peakResidentBytesAtStart": peakCheckpoints[0],
        "peakResidentBytesAfterFixture": peakCheckpoints[1],
        "peakResidentBytesAfterLegacyLoad": peakCheckpoints[2],
        "peakResidentBytesAfterMigration": peakCheckpoints[3],
        "peakResidentBytesAfterRecords": peakCheckpoints[4],
        "peakResidentBytesAfterQueries": peakCheckpoints[5],
      ],
      "load": ["legacyMilliseconds": legacyLoad.milliseconds, "segmentedMilliseconds": segmentedLoad.milliseconds],
      "seedEncodeMilliseconds": seed.milliseconds,
      "migration": [
        "milliseconds": migration.milliseconds,
        "bytesWritten": migrationIO.bytesWritten,
        "fileWriteCount": migrationIO.fileWriteCount,
        "segmentFileCount": migrationIO.segmentFileCount,
      ],
      "record": [
        "sampleCount": recordDurations.count,
        "p50Milliseconds": percentile(recordDurations, 0.50),
        "p95Milliseconds": percentile(recordDurations, 0.95),
        "maxMilliseconds": recordDurations.max() ?? 0,
      ],
      "steadyStatePersistence": [
        "sampleCount": flushDurations.count,
        "p50Milliseconds": percentile(flushDurations, 0.50),
        "p95Milliseconds": percentile(flushDurations, 0.95),
        "maxMilliseconds": flushDurations.max() ?? 0,
        "bytesWritten": steadyIO.bytesWritten,
        "fileWriteCount": steadyIO.fileWriteCount,
        "averageBytesPerWrite": averageWriteBytes,
        "projectedBytesWrittenPerHourAtOneWritePerMinute": averageWriteBytes * 60,
      ],
      "noOpFlush": [
        "milliseconds": noOp.milliseconds,
        "bytesWritten": noOpIO.bytesWritten,
        "fileWriteCount": noOpIO.fileWriteCount,
      ],
      "queries": queryResults,
      "networkSevenDayMilliseconds": network.milliseconds,
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: outputURL, options: .atomic)
  }

  private func configuration() throws -> BenchmarkConfiguration {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent(".macvitals-history-benchmark.json")
    guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Mature history benchmark is opt-in") }
    return try JSONDecoder().decode(BenchmarkConfiguration.self, from: Data(contentsOf: url))
  }

  private func writeLegacyFixture(
    to url: URL,
    bucketDuration: TimeInterval,
    bucketCount: Int,
    applicationsPerBucket: Int,
    firstBucketStart: TimeInterval
  ) throws -> (milliseconds: Double, bytes: UInt64) {
    var archive = HistoricalConsumptionArchive()
    for bucketIndex in 0..<bucketCount {
      let startedAt = Date(timeIntervalSince1970: firstBucketStart + Double(bucketIndex) * bucketDuration)
      var apps: [String: HistoricalConsumptionAggregate] = [:]
      for index in 0..<applicationsPerBucket {
        let usage = application(index: index, phase: bucketIndex)
        var aggregate = HistoricalConsumptionAggregate(application: usage)
        aggregate.add(application: usage, elapsed: bucketDuration)
        apps[usage.id] = aggregate
      }
      archive.buckets.append(HistoricalConsumptionBucket(startedAt: startedAt, applications: apps))
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try measureSync { try encoder.encode(archive) }
    try encoded.value.write(to: url, options: .atomic)
    return (encoded.milliseconds, try fileSize(url))
  }

  private func application(index: Int, phase: Int) -> ApplicationProcessUsage {
    let rotating = (index + phase) % 120
    return ApplicationProcessUsage(
      id: "benchmark.app.\(index)", name: "Benchmark App \(index)",
      bundleIdentifier: "benchmark.app.\(index)", representativePID: pid_t(1_000 + index),
      processCount: 1 + index % 4, cpuPercent: Double(1 + rotating) * 1.7,
      memoryBytes: UInt64(8 + 120 - rotating) * 1_048_576,
      energyWatts: index.isMultiple(of: 3) ? Double(1 + (index * 7 + phase) % 50) / 10 : nil,
      energyImpactScore: Double(1 + (index * 11 + phase) % 100),
      gpuActivityScore: Double(1 + (index * 17 + phase) % 100),
      diskBytesPerSecond: Double(1 + (index * 23 + phase) % 100) * 4_096,
      isGPUActivityEstimated: true, isEnergyEstimated: !index.isMultiple(of: 3))
  }

  private func snapshot(at date: Date, applications: [ApplicationProcessUsage]) -> ProcessMetricsSnapshot {
    ProcessMetricsSnapshot(timestamp: date, applications: applications, sampledProcessCount: applications.count,
      energyCountersAvailable: applications.contains { $0.energyWatts != nil })
  }

  private func measureSync<T>(_ operation: () throws -> T) rethrows -> (value: T, milliseconds: Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = try operation()
    return (value, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
  }

  private func measureAsync<T>(_ operation: () async -> T) async -> (value: T, milliseconds: Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let value = await operation()
    return (value, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
  }

  private func percentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * fraction)) - 1))]
  }

  private func fileSize(_ url: URL) throws -> UInt64 {
    try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber).uint64Value
  }

  private func directoryBytes(_ url: URL) throws -> UInt64 {
    try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      .reduce(into: UInt64(0)) { total, item in
        let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if values.isRegularFile == true, values.isSymbolicLink != true { total += try fileSize(item) }
      }
  }

  private func rawPeakRSS() throws -> UInt64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw BenchmarkError.invalidRSS }
    return UInt64(max(0, usage.ru_maxrss))
  }

  private func currentResidentKiB() throws -> UInt64 {
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-o", "rss=", "-p", String(getpid())]
    let pipe = Pipe(); process.standardOutput = pipe
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0,
      let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
      let value = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0
    else { throw BenchmarkError.invalidRSS }
    return value
  }

  private func calibratePeakRSS() throws -> PeakCalibration {
    let raw = try rawPeakRSS(), currentKiB = try currentResidentKiB(), currentBytes = currentKiB * 1_024
    let candidates: [(UInt64, UInt64)] = [(1, raw), (1_024, raw.multipliedReportingOverflow(by: 1_024).overflow ? UInt64.max : raw * 1_024)]
    let chosen = candidates.min { difference($0.1, currentBytes) < difference($1.1, currentBytes) }!
    let physical = ProcessInfo.processInfo.physicalMemory
    guard chosen.1 >= currentBytes / 2, chosen.1 <= physical else { throw BenchmarkError.invalidRSS }
    return PeakCalibration(raw: raw, currentKiB: currentKiB, scale: chosen.0, physicalMemory: physical)
  }

  private func peakRSSBytes(_ calibration: PeakCalibration) throws -> UInt64 {
    let result = (try rawPeakRSS()).multipliedReportingOverflow(by: calibration.scale)
    guard !result.overflow, result.partialValue <= calibration.physicalMemory else { throw BenchmarkError.invalidRSS }
    return result.partialValue
  }

  private func difference(_ a: UInt64, _ b: UInt64) -> UInt64 { a >= b ? a - b : b - a }

  private struct BenchmarkConfiguration: Decodable { let productBaseSHA: String; let benchmarkSHA: String; let outputPath: String }
  private struct PeakCalibration { let raw: UInt64; let currentKiB: UInt64; let scale: UInt64; let physicalMemory: UInt64 }
  private enum BenchmarkError: Error { case invalidRSS }
}
