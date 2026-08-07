import Darwin
import Foundation
import XCTest

@testable import MacVitals

final class HistoricalConsumptionBenchmarkTests: XCTestCase {
  func testMatureSevenDayArchiveBaseline() async throws {
    let configuration = try benchmarkConfiguration()
    let outputURL = URL(fileURLWithPath: configuration.outputPath)
    let temporaryRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("MacVitalsHistoryBenchmark-\(UUID().uuidString)", isDirectory: true)
    let archiveURL = temporaryRoot.appendingPathComponent(
      "consumption-history-v1.json",
      isDirectory: false)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)

    let memoryCalibration = try peakRSSCalibration()
    let peakRSSAtStart = try peakResidentBytes(using: memoryCalibration)
    let bucketDuration: TimeInterval = 5 * 60
    let bucketCount = Int(HistoricalConsumptionRange.sevenDays.duration / bucketDuration)
    let applicationsPerBucket = 24
    let currentBucketStart = floor(1_900_000_000 / bucketDuration) * bucketDuration
    let firstBucketStart = currentBucketStart - Double(bucketCount - 1) * bucketDuration

    let seed = try writeMatureArchive(
      to: archiveURL,
      bucketDuration: bucketDuration,
      bucketCount: bucketCount,
      applicationsPerBucket: applicationsPerBucket,
      firstBucketStart: firstBucketStart)
    let peakRSSAfterFixture = try peakResidentBytes(using: memoryCalibration)

    let legacyLoadMeasurement = measuredSync {
      HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    }
    let store = legacyLoadMeasurement.value
    let peakRSSAfterLegacyLoad = try peakResidentBytes(using: memoryCalibration)
    let benchmarkNow = Date(timeIntervalSince1970: currentBucketStart + 1)
    let sampledApplications = (0..<120).map { application(index: $0, phase: 10_000) }

    let migrationMeasurement = await measuredAsync {
      await store.record(
        snapshot: self.snapshot(at: benchmarkNow, applications: sampledApplications),
        elapsed: 1)
    }
    let migrationDiagnostics = await store.persistenceDiagnostics()
    XCTAssertTrue(migrationDiagnostics.segmentedPersistenceReady)
    XCTAssertGreaterThan(migrationDiagnostics.fileWriteCount, 100)
    XCTAssertGreaterThan(migrationDiagnostics.bytesWritten, 0)
    XCTAssertGreaterThan(migrationDiagnostics.segmentFileCount, 100)
    let peakRSSAfterMigration = try peakResidentBytes(using: memoryCalibration)

    await store.resetPersistenceDiagnostics()
    var recordDurations: [Double] = []
    recordDurations.reserveCapacity(120)
    for index in 0..<120 {
      let timestamp = benchmarkNow.addingTimeInterval(2 + Double(index) * 0.4)
      let measurement = await measuredAsync {
        await store.record(
          snapshot: self.snapshot(at: timestamp, applications: sampledApplications),
          elapsed: 0.4)
      }
      recordDurations.append(measurement.milliseconds)
    }
    let peakRSSAfterRecords = try peakResidentBytes(using: memoryCalibration)

    var flushDurations: [Double] = []
    flushDurations.reserveCapacity(3)
    for index in 0..<3 {
      if index > 0 {
        await store.record(
          snapshot: snapshot(
            at: benchmarkNow.addingTimeInterval(50 + Double(index) * 0.5),
            applications: sampledApplications),
          elapsed: 0.5)
      }
      let measurement = await measuredAsync {
        await store.flush()
      }
      flushDurations.append(measurement.milliseconds)
    }
    let steadyStateDiagnostics = await store.persistenceDiagnostics()
    XCTAssertEqual(steadyStateDiagnostics.fileWriteCount, 3)
    XCTAssertGreaterThan(steadyStateDiagnostics.bytesWritten, 0)
    XCTAssertEqual(steadyStateDiagnostics.dirtySegmentCount, 0)

    await store.resetPersistenceDiagnostics()
    let noOpFlushMeasurement = await measuredAsync {
      await store.flush()
    }
    let noOpDiagnostics = await store.persistenceDiagnostics()
    XCTAssertEqual(noOpDiagnostics.fileWriteCount, 0)
    XCTAssertEqual(noOpDiagnostics.bytesWritten, 0)

    let segmentedReloadMeasurement = measuredSync {
      HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    }
    let reloadedStore = segmentedReloadMeasurement.value
    let reloadedDiagnostics = await reloadedStore.persistenceDiagnostics()
    XCTAssertTrue(reloadedDiagnostics.segmentedPersistenceReady)
    XCTAssertEqual(reloadedDiagnostics.segmentFileCount, steadyStateDiagnostics.segmentFileCount)

    let supportedMetrics: [HistoricalConsumptionMetric] = [
      .cpu, .memory, .gpu, .energy, .disk, .thermal,
    ]
    var queryResults: [String: Any] = [:]
    for range in HistoricalConsumptionRange.allCases {
      for metric in supportedMetrics {
        var durations: [Double] = []
        var expectedIDs: [String]?
        for _ in 0..<5 {
          let measurement = await measuredAsync {
            await reloadedStore.leaders(metric: metric, range: range, now: benchmarkNow)
          }
          let ids = measurement.value.map(\.id)
          XCTAssertFalse(ids.isEmpty)
          if let expectedIDs {
            XCTAssertEqual(ids, expectedIDs)
          } else {
            expectedIDs = ids
          }
          durations.append(measurement.milliseconds)
        }
        queryResults["\(range.rawValue).\(metric.rawValue)"] = [
          "leaders": expectedIDs?.count ?? 0,
          "topLeaderIDs": Array((expectedIDs ?? []).prefix(20)),
          "p50Milliseconds": percentile(durations, fraction: 0.50),
          "p95Milliseconds": percentile(durations, fraction: 0.95),
          "maxMilliseconds": durations.max() ?? 0,
        ]
      }
    }

    let networkMeasurement = await measuredAsync {
      await reloadedStore.leaders(metric: .network, range: .sevenDays, now: benchmarkNow)
    }
    XCTAssertTrue(networkMeasurement.value.isEmpty)
    let peakRSSAfterQueries = try peakResidentBytes(using: memoryCalibration)

    let segmentDirectoryURL = HistoricalConsumptionArchiveStore.segmentDirectoryURL(for: archiveURL)
    let segmentedArchiveBytes = try directoryBytes(at: segmentDirectoryURL)
    let averageSteadyStateWriteBytes = Double(steadyStateDiagnostics.bytesWritten)
      / Double(max(1, steadyStateDiagnostics.fileWriteCount))
    let projectedHourlyWriteBytes = averageSteadyStateWriteBytes * 60

    let report: [String: Any] = [
      "schemaVersion": 4,
      "identity": [
        "productBaseSHA": configuration.productBaseSHA,
        "benchmarkSHA": configuration.benchmarkSHA,
      ],
      "fixture": [
        "bucketCount": bucketCount,
        "applicationsPerBucket": applicationsPerBucket,
        "aggregateCount": bucketCount * applicationsPerBucket,
        "seededLegacyArchiveBytes": seed.archiveBytes,
        "segmentedArchiveBytes": segmentedArchiveBytes,
        "segmentFileCount": steadyStateDiagnostics.segmentFileCount,
      ],
      "memory": [
        "semantics": "processLifetimePeakRSS",
        "unit": "bytes",
        "ruMaxRSSRawAtCalibration": memoryCalibration.rawPeakRSS,
        "currentResidentKiBAtCalibration": memoryCalibration.currentResidentKiB,
        "ruMaxRSSScaleToBytes": memoryCalibration.scaleToBytes,
        "systemPhysicalMemoryBytes": memoryCalibration.systemPhysicalMemoryBytes,
        "peakResidentBytesAtStart": peakRSSAtStart,
        "peakResidentBytesAfterFixture": peakRSSAfterFixture,
        "peakResidentBytesAfterLegacyLoad": peakRSSAfterLegacyLoad,
        "peakResidentBytesAfterMigration": peakRSSAfterMigration,
        "peakResidentBytesAfterRecords": peakRSSAfterRecords,
        "peakResidentBytesAfterQueries": peakRSSAfterQueries,
      ],
      "load": [
        "legacyMilliseconds": legacyLoadMeasurement.milliseconds,
        "segmentedMilliseconds": segmentedReloadMeasurement.milliseconds,
      ],
      "seedEncodeMilliseconds": seed.encodeMilliseconds,
      "migration": [
        "milliseconds": migrationMeasurement.milliseconds,
        "bytesWritten": migrationDiagnostics.bytesWritten,
        "fileWriteCount": migrationDiagnostics.fileWriteCount,
        "segmentFileCount": migrationDiagnostics.segmentFileCount,
      ],
      "record": [
        "sampleCount": recordDurations.count,
        "p50Milliseconds": percentile(recordDurations, fraction: 0.50),
        "p95Milliseconds": percentile(recordDurations, fraction: 0.95),
        "maxMilliseconds": recordDurations.max() ?? 0,
      ],
      "steadyStatePersistence": [
        "sampleCount": flushDurations.count,
        "p50Milliseconds": percentile(flushDurations, fraction: 0.50),
        "p95Milliseconds": percentile(flushDurations, fraction: 0.95),
        "maxMilliseconds": flushDurations.max() ?? 0,
        "bytesWritten": steadyStateDiagnostics.bytesWritten,
        "fileWriteCount": steadyStateDiagnostics.fileWriteCount,
        "averageBytesPerWrite": averageSteadyStateWriteBytes,
        "projectedBytesWrittenPerHourAtOneWritePerMinute": projectedHourlyWriteBytes,
      ],
      "noOpFlush": [
        "milliseconds": noOpFlushMeasurement.milliseconds,
        "bytesWritten": noOpDiagnostics.bytesWritten,
        "fileWriteCount": noOpDiagnostics.fileWriteCount,
      ],
      "queries": queryResults,
      "networkSevenDayMilliseconds": networkMeasurement.milliseconds,
    ]

    let reportData = try JSONSerialization.data(
      withJSONObject: report,
      options: [.prettyPrinted, .sortedKeys])
    try reportData.write(to: outputURL, options: .atomic)
    XCTAssertGreaterThan(reportData.count, 0)
  }

  private func benchmarkConfiguration() throws -> BenchmarkConfiguration {
    let sourceURL = URL(fileURLWithPath: #filePath)
    let projectRoot = sourceURL.deletingLastPathComponent().deletingLastPathComponent()
    let configurationURL = projectRoot.appendingPathComponent(
      ".macvitals-history-benchmark.json",
      isDirectory: false)
    guard FileManager.default.fileExists(atPath: configurationURL.path) else {
      throw XCTSkip("Mature history benchmark is opt-in")
    }
    let data = try Data(contentsOf: configurationURL)
    return try JSONDecoder().decode(BenchmarkConfiguration.self, from: data)
  }

  private func writeMatureArchive(
    to archiveURL: URL,
    bucketDuration: TimeInterval,
    bucketCount: Int,
    applicationsPerBucket: Int,
    firstBucketStart: TimeInterval
  ) throws -> (encodeMilliseconds: Double, archiveBytes: UInt64) {
    var archive = HistoricalConsumptionArchive()
    archive.buckets.reserveCapacity(bucketCount)

    for bucketIndex in 0..<bucketCount {
      let startedAt = Date(
        timeIntervalSince1970: firstBucketStart + Double(bucketIndex) * bucketDuration)
      var applications: [String: HistoricalConsumptionAggregate] = [:]
      applications.reserveCapacity(applicationsPerBucket)
      for applicationIndex in 0..<applicationsPerBucket {
        let usage = application(index: applicationIndex, phase: bucketIndex)
        var aggregate = HistoricalConsumptionAggregate(application: usage)
        aggregate.add(application: usage, elapsed: bucketDuration)
        applications[usage.id] = aggregate
      }
      archive.buckets.append(
        HistoricalConsumptionBucket(startedAt: startedAt, applications: applications))
    }

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    let encodeMeasurement = try measuredSync {
      try encoder.encode(archive)
    }
    try encodeMeasurement.value.write(to: archiveURL, options: .atomic)
    return (
      encodeMilliseconds: encodeMeasurement.milliseconds,
      archiveBytes: try fileSize(at: archiveURL))
  }

  private func application(index: Int, phase: Int) -> ApplicationProcessUsage {
    let rotating = (index + phase) % 120
    let reverse = 120 - rotating
    return ApplicationProcessUsage(
      id: "benchmark.app.\(index)",
      name: "Benchmark App \(index)",
      bundleIdentifier: "benchmark.app.\(index)",
      representativePID: pid_t(1_000 + index),
      processCount: 1 + index % 4,
      cpuPercent: Double(1 + rotating) * 1.7,
      memoryBytes: UInt64(8 + reverse) * 1_048_576,
      energyWatts: index.isMultiple(of: 3) ? Double(1 + (index * 7 + phase) % 50) / 10 : nil,
      energyImpactScore: Double(1 + (index * 11 + phase) % 100),
      gpuActivityScore: Double(1 + (index * 17 + phase) % 100),
      diskBytesPerSecond: Double(1 + (index * 23 + phase) % 100) * 4_096,
      isGPUActivityEstimated: true,
      isEnergyEstimated: !index.isMultiple(of: 3))
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

  private func measuredSync<Value>(
    _ operation: () throws -> Value
  ) rethrows -> (value: Value, milliseconds: Double) {
    let started = DispatchTime.now().uptimeNanoseconds
    let value = try operation()
    let finished = DispatchTime.now().uptimeNanoseconds
    return (value, milliseconds(started: started, finished: finished))
  }

  private func measuredAsync<Value>(
    _ operation: () async -> Value
  ) async -> (value: Value, milliseconds: Double) {
    let started = DispatchTime.now().uptimeNanoseconds
    let value = await operation()
    let finished = DispatchTime.now().uptimeNanoseconds
    return (value, milliseconds(started: started, finished: finished))
  }

  private func milliseconds(started: UInt64, finished: UInt64) -> Double {
    Double(finished &- started) / 1_000_000
  }

  private func percentile(_ values: [Double], fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let rank = max(1, Int(ceil(Double(sorted.count) * fraction)))
    return sorted[min(sorted.count - 1, rank - 1)]
  }

  private func fileSize(at url: URL) throws -> UInt64 {
    try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
    ).uint64Value
  }

  private func directoryBytes(at directoryURL: URL) throws -> UInt64 {
    var total: UInt64 = 0
    for url in try FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles])
    {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
      let size = try fileSize(at: url)
      let (updated, overflow) = total.addingReportingOverflow(size)
      if overflow {
        throw BenchmarkError.message("segmented archive size overflowed")
      }
      total = updated
    }
    return total
  }

  private func rawPeakRSS() throws -> UInt64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
      throw BenchmarkError.message("getrusage(RUSAGE_SELF) failed")
    }
    return UInt64(max(0, usage.ru_maxrss))
  }

  private func currentResidentKiB() throws -> UInt64 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-o", "rss=", "-p", String(getpid())]
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let message = String(
        data: errors.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8) ?? "unknown ps error"
      throw BenchmarkError.message(
        "ps RSS probe failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    let text = String(
      data: output.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8) ?? ""
    guard let value = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
      throw BenchmarkError.message("ps RSS probe returned an invalid value: \(text)")
    }
    return value
  }

  private func peakRSSCalibration() throws -> PeakRSSCalibration {
    let raw = try rawPeakRSS()
    let currentKiB = try currentResidentKiB()
    let (currentBytes, currentOverflow) = currentKiB.multipliedReportingOverflow(by: 1_024)
    guard !currentOverflow, currentBytes > 0, raw > 0 else {
      throw BenchmarkError.message("peak RSS calibration inputs are invalid")
    }

    let (scaledKiB, scaledKiBOverflow) = raw.multipliedReportingOverflow(by: 1_024)
    let candidates: [(scale: UInt64, bytes: UInt64)] = [
      (1, raw),
      (1_024, scaledKiBOverflow ? UInt64.max : scaledKiB),
    ]
    let chosen = candidates.min { lhs, rhs in
      absoluteDifference(lhs.bytes, currentBytes) < absoluteDifference(rhs.bytes, currentBytes)
    }!

    let physicalMemory = ProcessInfo.processInfo.physicalMemory
    guard chosen.bytes >= currentBytes / 2 else {
      throw BenchmarkError.message(
        "calibrated peak RSS is implausibly below current RSS: peak=\(chosen.bytes) current=\(currentBytes)")
    }
    guard chosen.bytes <= physicalMemory else {
      throw BenchmarkError.message(
        "calibrated peak RSS exceeds physical memory: peak=\(chosen.bytes) physical=\(physicalMemory)")
    }

    return PeakRSSCalibration(
      rawPeakRSS: raw,
      currentResidentKiB: currentKiB,
      scaleToBytes: chosen.scale,
      systemPhysicalMemoryBytes: physicalMemory)
  }

  private func peakResidentBytes(using calibration: PeakRSSCalibration) throws -> UInt64 {
    let raw = try rawPeakRSS()
    let (value, overflow) = raw.multipliedReportingOverflow(by: calibration.scaleToBytes)
    guard !overflow else {
      throw BenchmarkError.message("peak RSS conversion overflowed")
    }
    guard value <= calibration.systemPhysicalMemoryBytes else {
      throw BenchmarkError.message(
        "peak RSS exceeds physical memory after calibration: peak=\(value) physical=\(calibration.systemPhysicalMemoryBytes)")
    }
    return value
  }

  private func absoluteDifference(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    lhs >= rhs ? lhs - rhs : rhs - lhs
  }

  private struct BenchmarkConfiguration: Decodable {
    let productBaseSHA: String
    let benchmarkSHA: String
    let outputPath: String
  }

  private struct PeakRSSCalibration {
    let rawPeakRSS: UInt64
    let currentResidentKiB: UInt64
    let scaleToBytes: UInt64
    let systemPhysicalMemoryBytes: UInt64
  }

  private enum BenchmarkError: Error {
    case message(String)
  }
}
