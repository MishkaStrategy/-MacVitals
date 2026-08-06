import Darwin
import Foundation
import XCTest

@testable import MacVitals

final class HistoricalConsumptionBenchmarkTests: XCTestCase {
  func testMatureSevenDayArchiveBaseline() async throws {
    guard ProcessInfo.processInfo.environment["MACVITALS_RUN_HISTORY_BENCHMARK"] == "1"
    else {
      throw XCTSkip("Mature history benchmark is opt-in")
    }

    let outputPath = try XCTUnwrap(
      ProcessInfo.processInfo.environment["MACVITALS_HISTORY_BENCHMARK_OUTPUT"])
    let outputURL = URL(fileURLWithPath: outputPath)
    let temporaryRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("MacVitalsHistoryBenchmark-\(UUID().uuidString)", isDirectory: true)
    let archiveURL = temporaryRoot.appendingPathComponent(
      "consumption-history-v1.json",
      isDirectory: false)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    try FileManager.default.createDirectory(
      at: temporaryRoot,
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true)

    let bucketDuration: TimeInterval = 5 * 60
    let bucketCount = Int(HistoricalConsumptionRange.sevenDays.duration / bucketDuration)
    let applicationsPerBucket = 24
    let currentBucketStart = floor(1_900_000_000 / bucketDuration) * bucketDuration
    let firstBucketStart = currentBucketStart - Double(bucketCount - 1) * bucketDuration
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
    let seedEncode = measuredSync {
      try encoder.encode(archive)
    }
    try seedEncode.value.write(to: archiveURL, options: .atomic)
    let seededArchiveBytes = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: archiveURL.path)[.size] as? NSNumber)
      .uint64Value

    let loadMeasurement = measuredSync {
      HistoricalConsumptionArchiveStore(archiveURL: archiveURL)
    }
    let store = loadMeasurement.value
    let benchmarkNow = Date(timeIntervalSince1970: currentBucketStart + 1)
    let sampledApplications = (0..<120).map { application(index: $0, phase: 10_000) }

    let recordWithPersistence = await measuredAsync {
      await store.record(
        snapshot: self.snapshot(at: benchmarkNow, applications: sampledApplications),
        elapsed: 1)
    }

    var recordDurations: [Double] = []
    recordDurations.reserveCapacity(120)
    for index in 0..<120 {
      let timestamp = benchmarkNow.addingTimeInterval(1 + Double(index) * 0.4)
      let measurement = await measuredAsync {
        await store.record(
          snapshot: self.snapshot(at: timestamp, applications: sampledApplications),
          elapsed: 0.4)
      }
      recordDurations.append(measurement.milliseconds)
    }

    var flushDurations: [Double] = []
    flushDurations.reserveCapacity(3)
    for _ in 0..<3 {
      let measurement = await measuredAsync {
        await store.flush()
      }
      flushDurations.append(measurement.milliseconds)
    }

    let supportedMetrics: [HistoricalConsumptionMetric] = [
      .cpu, .memory, .gpu, .energy, .disk, .thermal,
    ]
    var queryResults: [String: Any] = [:]
    for range in HistoricalConsumptionRange.allCases {
      for metric in supportedMetrics {
        var durations: [Double] = []
        var leaderCount = 0
        for _ in 0..<5 {
          let measurement = await measuredAsync {
            await store.leaders(metric: metric, range: range, now: benchmarkNow)
          }
          leaderCount = measurement.value.count
          durations.append(measurement.milliseconds)
        }
        XCTAssertGreaterThan(leaderCount, 0)
        queryResults["\(range.rawValue).\(metric.rawValue)"] = [
          "leaders": leaderCount,
          "p50Milliseconds": percentile(durations, fraction: 0.50),
          "p95Milliseconds": percentile(durations, fraction: 0.95),
          "maxMilliseconds": durations.max() ?? 0,
        ]
      }
    }

    let networkMeasurement = await measuredAsync {
      await store.leaders(metric: .network, range: .sevenDays, now: benchmarkNow)
    }
    XCTAssertTrue(networkMeasurement.value.isEmpty)

    let finalArchiveBytes = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: archiveURL.path)[.size] as? NSNumber)
      .uint64Value
    let report: [String: Any] = [
      "schemaVersion": 1,
      "sourceSHA": ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "local",
      "fixture": [
        "bucketCount": bucketCount,
        "applicationsPerBucket": applicationsPerBucket,
        "seededArchiveBytes": seededArchiveBytes,
        "finalArchiveBytes": finalArchiveBytes,
      ],
      "loadMilliseconds": loadMeasurement.milliseconds,
      "seedEncodeMilliseconds": seedEncode.milliseconds,
      "record": [
        "p50Milliseconds": percentile(recordDurations, fraction: 0.50),
        "p95Milliseconds": percentile(recordDurations, fraction: 0.95),
        "maxMilliseconds": recordDurations.max() ?? 0,
        "recordWithPersistenceMilliseconds": recordWithPersistence.milliseconds,
      ],
      "flush": [
        "p50Milliseconds": percentile(flushDurations, fraction: 0.50),
        "p95Milliseconds": percentile(flushDurations, fraction: 0.95),
        "maxMilliseconds": flushDurations.max() ?? 0,
        "estimatedBytesWrittenPerHour": Double(finalArchiveBytes) * 60,
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
}
