import Foundation
import OSLog

nonisolated struct HistoricalConsumptionPersistenceDiagnostics: Sendable, Equatable {
  let bytesWritten: UInt64
  let fileWriteCount: Int
  let segmentFileCount: Int
  let dirtySegmentCount: Int
  let segmentedPersistenceReady: Bool
}

actor HistoricalConsumptionArchiveStore {
  private let bucketDuration: TimeInterval = 5 * 60
  private let retentionDuration: TimeInterval = 7 * 24 * 60 * 60
  private let segmentDuration: TimeInterval = 60 * 60
  private let archiveURL: URL
  private let segmentDirectoryURL: URL
  private let formatMarkerURL: URL
  private var archive: HistoricalConsumptionArchive
  private var segmentedPersistenceReady: Bool
  private var dirtySegmentStarts = Set<Int64>()
  private var needsSegmentPrune = false
  private var lastPersistedAt = Date.distantPast
  private var persistenceBytesWritten: UInt64 = 0
  private var persistenceFileWriteCount = 0

  init(fileName: String = "consumption-history-v1.json") {
    let archiveURL = Self.makeArchiveURL(fileName: fileName)
    let segmentDirectoryURL = Self.segmentDirectoryURL(for: archiveURL)
    let state = Self.loadState(
      legacyURL: archiveURL,
      segmentDirectoryURL: segmentDirectoryURL)
    self.archiveURL = archiveURL
    self.segmentDirectoryURL = segmentDirectoryURL
    formatMarkerURL = segmentDirectoryURL.appendingPathComponent("FORMAT.json", isDirectory: false)
    archive = state.archive
    segmentedPersistenceReady = state.segmentedPersistenceReady
  }

  init(archiveURL: URL) {
    let segmentDirectoryURL = Self.segmentDirectoryURL(for: archiveURL)
    let state = Self.loadState(
      legacyURL: archiveURL,
      segmentDirectoryURL: segmentDirectoryURL)
    self.archiveURL = archiveURL
    self.segmentDirectoryURL = segmentDirectoryURL
    formatMarkerURL = segmentDirectoryURL.appendingPathComponent("FORMAT.json", isDirectory: false)
    archive = state.archive
    segmentedPersistenceReady = state.segmentedPersistenceReady
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
    dirtySegmentStarts.insert(Self.segmentStart(for: bucketStart))

    dirtySegmentStarts.formUnion(pruneAndCompact(now: snapshot.timestamp))
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
    _ = persist()
  }

  func persistenceDiagnostics() -> HistoricalConsumptionPersistenceDiagnostics {
    HistoricalConsumptionPersistenceDiagnostics(
      bytesWritten: persistenceBytesWritten,
      fileWriteCount: persistenceFileWriteCount,
      segmentFileCount: Self.segmentFileCount(in: segmentDirectoryURL),
      dirtySegmentCount: dirtySegmentStarts.count,
      segmentedPersistenceReady: segmentedPersistenceReady)
  }

  func resetPersistenceDiagnostics() {
    persistenceBytesWritten = 0
    persistenceFileWriteCount = 0
  }

  nonisolated static func segmentDirectoryURL(for archiveURL: URL) -> URL {
    archiveURL.appendingPathExtension("segments")
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

  private func pruneAndCompact(now: Date) -> Set<Int64> {
    var changedSegments = Set<Int64>()
    let cutoff = now.addingTimeInterval(-retentionDuration - bucketDuration)
    let removedSegmentStarts = Set(
      archive.buckets.lazy
        .filter { $0.startedAt < cutoff }
        .map { Self.segmentStart(for: $0.startedAt) })
    if !removedSegmentStarts.isEmpty {
      archive.buckets.removeAll { $0.startedAt < cutoff }
      changedSegments.formUnion(removedSegmentStarts)
      needsSegmentPrune = true
    }

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
      let compacted = applications.filter { selectedIDs.contains($0.key) }
      if compacted.count != applications.count {
        archive.buckets[index].applications = compacted
        changedSegments.insert(Self.segmentStart(for: archive.buckets[index].startedAt))
      }
    }
    return changedSegments
  }

  private func persistIfNeeded(now: Date) {
    guard now.timeIntervalSince(lastPersistedAt) >= 60 else { return }
    if persist() {
      lastPersistedAt = now
    }
  }

  @discardableResult
  private func persist() -> Bool {
    if segmentedPersistenceReady && dirtySegmentStarts.isEmpty && !needsSegmentPrune {
      return true
    }

    do {
      try ensureSegmentDirectory()
      let grouped = Dictionary(grouping: archive.buckets) {
        Self.segmentStart(for: $0.startedAt)
      }
      let activeSegmentStarts = Set(grouped.keys)
      let segmentsToWrite = segmentedPersistenceReady
        ? dirtySegmentStarts
        : activeSegmentStarts

      for segmentStart in segmentsToWrite.sorted() {
        let buckets = (grouped[segmentStart] ?? []).sorted { $0.startedAt < $1.startedAt }
        if buckets.isEmpty {
          try removeSegmentFileIfPresent(segmentStart: segmentStart)
        } else {
          try writeSegment(segmentStart: segmentStart, buckets: buckets)
        }
      }

      if !segmentedPersistenceReady || needsSegmentPrune {
        try removeObsoleteSegmentFiles(activeSegmentStarts: activeSegmentStarts)
      }

      if !segmentedPersistenceReady {
        try writeFormatMarker()
        segmentedPersistenceReady = true
        do {
          if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
          }
        } catch {
          Logger.persistence.warning(
            "Historical legacy archive cleanup failed after migration: \(error.localizedDescription, privacy: .public)")
        }
      }

      dirtySegmentStarts.removeAll(keepingCapacity: true)
      needsSegmentPrune = false
      return true
    } catch {
      Logger.persistence.error(
        "Historical segmented persistence failed: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  private func ensureSegmentDirectory() throws {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: segmentDirectoryURL.path, isDirectory: &isDirectory) {
      let values = try segmentDirectoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard isDirectory.boolValue, values.isDirectory == true, values.isSymbolicLink != true else {
        throw PersistenceError.unsafeSegmentDirectory
      }
      return
    }
    try fileManager.createDirectory(
      at: segmentDirectoryURL,
      withIntermediateDirectories: true)
  }

  private func writeSegment(
    segmentStart: Int64,
    buckets: [HistoricalConsumptionBucket]
  ) throws {
    let encoder = Self.makeEncoder()
    let segment = PersistedSegment(
      schemaVersion: 1,
      segmentStartEpochSeconds: segmentStart,
      buckets: buckets)
    let data = try encoder.encode(segment)
    try data.write(to: Self.segmentFileURL(in: segmentDirectoryURL, segmentStart: segmentStart), options: .atomic)
    recordPersistenceWrite(bytes: data.count)
  }

  private func writeFormatMarker() throws {
    let marker = SegmentFormatMarker(schemaVersion: 1, segmentDurationSeconds: Int(segmentDuration))
    let data = try JSONEncoder().encode(marker)
    try data.write(to: formatMarkerURL, options: .atomic)
    recordPersistenceWrite(bytes: data.count)
  }

  private func removeSegmentFileIfPresent(segmentStart: Int64) throws {
    let url = Self.segmentFileURL(in: segmentDirectoryURL, segmentStart: segmentStart)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }

  private func removeObsoleteSegmentFiles(activeSegmentStarts: Set<Int64>) throws {
    for (segmentStart, url) in try Self.segmentFiles(in: segmentDirectoryURL) {
      if !activeSegmentStarts.contains(segmentStart) {
        try FileManager.default.removeItem(at: url)
      }
    }
  }

  private func recordPersistenceWrite(bytes: Int) {
    persistenceFileWriteCount += 1
    let byteCount = UInt64(max(0, bytes))
    let (updated, overflow) = persistenceBytesWritten.addingReportingOverflow(byteCount)
    persistenceBytesWritten = overflow ? UInt64.max : updated
  }

  private static func loadState(
    legacyURL: URL,
    segmentDirectoryURL: URL
  ) -> LoadedState {
    if hasValidFormatMarker(in: segmentDirectoryURL) {
      return LoadedState(
        archive: loadSegmentedArchive(from: segmentDirectoryURL),
        segmentedPersistenceReady: true)
    }
    return LoadedState(
      archive: loadLegacyArchive(from: legacyURL),
      segmentedPersistenceReady: false)
  }

  private static func loadLegacyArchive(from url: URL) -> HistoricalConsumptionArchive {
    guard let data = try? Data(contentsOf: url) else { return HistoricalConsumptionArchive() }
    let decoder = makeDecoder()
    guard let decoded = try? decoder.decode(HistoricalConsumptionArchive.self, from: data),
      decoded.schemaVersion == 1
    else {
      return HistoricalConsumptionArchive()
    }
    return decoded
  }

  private static func loadSegmentedArchive(from directoryURL: URL) -> HistoricalConsumptionArchive {
    var bucketsByStart: [Date: HistoricalConsumptionBucket] = [:]
    do {
      for (segmentStart, url) in try segmentFiles(in: directoryURL) {
        guard let data = try? Data(contentsOf: url),
          let segment = try? makeDecoder().decode(PersistedSegment.self, from: data),
          segment.schemaVersion == 1,
          segment.segmentStartEpochSeconds == segmentStart,
          segment.buckets.allSatisfy({ Self.segmentStart(for: $0.startedAt) == segmentStart })
        else {
          Logger.persistence.error(
            "Historical segment rejected as corrupt or inconsistent: \(url.lastPathComponent, privacy: .public)")
          continue
        }
        for bucket in segment.buckets {
          if bucketsByStart[bucket.startedAt] == nil {
            bucketsByStart[bucket.startedAt] = bucket
          } else {
            Logger.persistence.error(
              "Duplicate historical bucket rejected at \(bucket.startedAt.timeIntervalSince1970, privacy: .public)")
          }
        }
      }
    } catch {
      Logger.persistence.error(
        "Historical segment directory could not be read: \(error.localizedDescription, privacy: .public)")
    }
    var archive = HistoricalConsumptionArchive()
    archive.buckets = bucketsByStart.values.sorted { $0.startedAt < $1.startedAt }
    return archive
  }

  private static func hasValidFormatMarker(in directoryURL: URL) -> Bool {
    let markerURL = directoryURL.appendingPathComponent("FORMAT.json", isDirectory: false)
    guard let values = try? markerURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
      values.isRegularFile == true,
      values.isSymbolicLink != true,
      let data = try? Data(contentsOf: markerURL),
      let marker = try? JSONDecoder().decode(SegmentFormatMarker.self, from: data)
    else {
      return false
    }
    return marker.schemaVersion == 1 && marker.segmentDurationSeconds == 3_600
  }

  private static func segmentFiles(in directoryURL: URL) throws -> [(Int64, URL)] {
    let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw PersistenceError.unsafeSegmentDirectory
    }
    let urls = try FileManager.default.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles])
    return urls.compactMap { url in
      guard let segmentStart = segmentStart(fromFileName: url.lastPathComponent),
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
        values.isRegularFile == true,
        values.isSymbolicLink != true
      else {
        return nil
      }
      return (segmentStart, url)
    }.sorted { $0.0 < $1.0 }
  }

  private static func segmentFileCount(in directoryURL: URL) -> Int {
    (try? segmentFiles(in: directoryURL).count) ?? 0
  }

  private static func segmentStart(fromFileName name: String) -> Int64? {
    let prefix = "segment-"
    let suffix = ".json"
    guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
    let start = name.index(name.startIndex, offsetBy: prefix.count)
    let end = name.index(name.endIndex, offsetBy: -suffix.count)
    return Int64(name[start..<end])
  }

  private static func segmentFileURL(in directoryURL: URL, segmentStart: Int64) -> URL {
    directoryURL.appendingPathComponent("segment-\(segmentStart).json", isDirectory: false)
  }

  private static func segmentStart(for date: Date) -> Int64 {
    Int64(floor(date.timeIntervalSince1970 / 3_600) * 3_600)
  }

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
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

  private struct LoadedState {
    let archive: HistoricalConsumptionArchive
    let segmentedPersistenceReady: Bool
  }

  private struct PersistedSegment: Codable {
    let schemaVersion: Int
    let segmentStartEpochSeconds: Int64
    let buckets: [HistoricalConsumptionBucket]
  }

  private struct SegmentFormatMarker: Codable {
    let schemaVersion: Int
    let segmentDurationSeconds: Int
  }

  private enum PersistenceError: Error {
    case unsafeSegmentDirectory
  }
}
