import Foundation
import OSLog

actor HistoricalConsumptionArchiveStore {
  private let bucketDuration: TimeInterval = 5 * 60
  private let retentionDuration: TimeInterval = 7 * 24 * 60 * 60
  private let archiveURL: URL
  private var archive: HistoricalConsumptionArchive
  private var lastPersistedAt = Date.distantPast

  init(fileName: String = "consumption-history-v1.json") {
    let archiveURL = Self.makeArchiveURL(fileName: fileName)
    self.archiveURL = archiveURL
    archive = Self.loadArchive(from: archiveURL)
  }

  init(archiveURL: URL) {
    self.archiveURL = archiveURL
    archive = Self.loadArchive(from: archiveURL)
  }

  func record(snapshot: ProcessMetricsSnapshot, elapsed: TimeInterval) {
    guard elapsed.isFinite, elapsed > 0.25 else { return }
    let boundedElapsed = min(60, elapsed)
    let candidates = selectedApplications(from: snapshot.applications)
    guard !candidates.isEmpty else { return }

    let bucketStart = Date(
      timeIntervalSince1970:
        floor(snapshot.timestamp.timeIntervalSince1970 / bucketDuration) * bucketDuration)
    if archive.buckets.last?.startedAt != bucketStart {
      archive.buckets.append(
        HistoricalConsumptionBucket(startedAt: bucketStart, applications: [:]))
    }

    guard var bucket = archive.buckets.popLast() else { return }
    for application in candidates {
      var aggregate = bucket.applications[application.id]
        ?? HistoricalConsumptionAggregate(application: application)
      aggregate.add(application: application, elapsed: boundedElapsed)
      bucket.applications[application.id] = aggregate
    }
    archive.buckets.append(bucket)

    pruneAndCompact(now: snapshot.timestamp)
    persistIfNeeded(now: snapshot.timestamp)
  }

  func leaders(
    metric: HistoricalConsumptionMetric,
    range: HistoricalConsumptionRange,
    now: Date = Date()
  ) -> [HistoricalConsumptionLeader] {
    guard metric != .network else { return [] }
    let cutoff = now.addingTimeInterval(-range.duration)
    var merged: [String: HistoricalConsumptionAggregate] = [:]

    for bucket in archive.buckets
    where bucket.startedAt.addingTimeInterval(bucketDuration) >= cutoff {
      for (id, aggregate) in bucket.applications {
        if var existing = merged[id] {
          existing.merge(aggregate)
          merged[id] = existing
        } else {
          merged[id] = aggregate
        }
      }
    }

    return merged.values
      .filter { $0.score(for: metric) > 0 }
      .sorted { Self.ranksBefore($0, $1, metric: metric) }
      .map(\.leader)
  }

  func coverageDuration(
    range: HistoricalConsumptionRange,
    now: Date = Date()
  ) -> TimeInterval {
    guard let first = archive.buckets.first?.startedAt else { return 0 }
    return min(range.duration, max(0, now.timeIntervalSince(first)))
  }

  func firstRecordedAt() -> Date? {
    archive.buckets.first?.startedAt
  }

  func flush() {
    persist()
  }

  private func selectedApplications(
    from applications: [ApplicationProcessUsage]
  ) -> [ApplicationProcessUsage] {
    let useful = applications.filter {
      $0.cpuPercent > 0.01
        || $0.memoryBytes > 1_048_576
        || $0.gpuActivityScore > 0.01
        || $0.energyImpactScore > 0.01
        || $0.diskBytesPerSecond > 1
    }
    var selectedIDs = Set<String>()
    let selectors: [(ApplicationProcessUsage) -> Double] = [
      { $0.cpuPercent },
      { Double($0.memoryBytes) },
      { $0.gpuActivityScore },
      { $0.energyWatts ?? $0.energyImpactScore },
      { $0.diskBytesPerSecond },
    ]
    for selector in selectors {
      for application in useful
        .sorted(by: { Self.ranksBefore($0, $1, score: selector) })
        .prefix(15)
      {
        selectedIDs.insert(application.id)
      }
    }
    return useful.filter { selectedIDs.contains($0.id) }
  }

  private func pruneAndCompact(now: Date) {
    let cutoff = now.addingTimeInterval(-retentionDuration - bucketDuration)
    archive.buckets.removeAll { $0.startedAt < cutoff }

    for index in archive.buckets.indices {
      guard archive.buckets[index].applications.count > 90 else { continue }
      let applications = archive.buckets[index].applications
      var selectedIDs = Set<String>()
      let metrics: [HistoricalConsumptionMetric] = [
        .cpu, .memory, .gpu, .energy, .disk, .thermal,
      ]
      for metric in metrics {
        for aggregate in applications.values
          .sorted(by: { Self.ranksBefore($0, $1, metric: metric) })
          .prefix(15)
        {
          selectedIDs.insert(aggregate.id)
        }
      }
      archive.buckets[index].applications = applications.filter {
        selectedIDs.contains($0.key)
      }
    }
  }

  private func persistIfNeeded(now: Date) {
    guard now.timeIntervalSince(lastPersistedAt) >= 60 else { return }
    lastPersistedAt = now
    persist()
  }

  private func persist() {
    do {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .millisecondsSince1970
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(archive)
      try FileManager.default.createDirectory(
        at: archiveURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      try data.write(to: archiveURL, options: .atomic)
    } catch {
      Logger.persistence.error(
        "Historical consumption persistence failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private static func ranksBefore(
    _ lhs: ApplicationProcessUsage,
    _ rhs: ApplicationProcessUsage,
    score: (ApplicationProcessUsage) -> Double
  ) -> Bool {
    ranksBefore(
      leftScore: score(lhs),
      rightScore: score(rhs),
      leftName: lhs.name,
      rightName: rhs.name,
      leftID: lhs.id,
      rightID: rhs.id)
  }

  private static func ranksBefore(
    _ lhs: HistoricalConsumptionAggregate,
    _ rhs: HistoricalConsumptionAggregate,
    metric: HistoricalConsumptionMetric
  ) -> Bool {
    ranksBefore(
      leftScore: lhs.score(for: metric),
      rightScore: rhs.score(for: metric),
      leftName: lhs.name,
      rightName: rhs.name,
      leftID: lhs.id,
      rightID: rhs.id)
  }

  private static func ranksBefore(
    leftScore: Double,
    rightScore: Double,
    leftName: String,
    rightName: String,
    leftID: String,
    rightID: String
  ) -> Bool {
    if leftScore != rightScore {
      return leftScore > rightScore
    }
    let nameOrder = leftName.localizedCaseInsensitiveCompare(rightName)
    if nameOrder != .orderedSame {
      return nameOrder == .orderedAscending
    }
    return leftID < rightID
  }

  private static func makeArchiveURL(fileName: String) -> URL {
    let root = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory
    return root.appendingPathComponent("MacVitals", isDirectory: true)
      .appendingPathComponent(fileName, isDirectory: false)
  }

  private static func loadArchive(from url: URL) -> HistoricalConsumptionArchive {
    guard let data = try? Data(contentsOf: url) else { return HistoricalConsumptionArchive() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    guard let decoded = try? decoder.decode(HistoricalConsumptionArchive.self, from: data),
      decoded.schemaVersion == 1
    else {
      return HistoricalConsumptionArchive()
    }
    return decoded
  }
}
