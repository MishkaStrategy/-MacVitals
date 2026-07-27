import Darwin
import Foundation

nonisolated enum FanControlRecoveryStoreError: LocalizedError, Sendable {
  case invalidDirectory
  case invalidLedger
  case unsafeOwnership
  case unsafePermissions
  case oversizedLedger
  case ioFailure(String)

  var errorDescription: String? {
    switch self {
    case .invalidDirectory:
      return "Fan recovery directory is invalid"
    case .invalidLedger:
      return "Fan recovery ledger is invalid"
    case .unsafeOwnership:
      return "Fan recovery ledger ownership is unsafe"
    case .unsafePermissions:
      return "Fan recovery ledger permissions are unsafe"
    case .oversizedLedger:
      return "Fan recovery ledger is unexpectedly large"
    case .ioFailure(let message):
      return "Fan recovery ledger I/O failed: \(message)"
    }
  }
}

private struct FanControlRecoveryDocument: Codable, Sendable, Equatable {
  struct Entry: Codable, Sendable, Equatable {
    let fanIndex: Int
    let deadlineEpochSeconds: Double
  }

  let schemaVersion: Int
  let entries: [Entry]
}

final class FanControlRecoveryStore: @unchecked Sendable {
  static let defaultURL = URL(
    fileURLWithPath: "/var/db/com.mishkacher.MacVitals/fan-control-recovery-v1.json",
    isDirectory: false)

  private static let schemaVersion = 1
  private static let maximumLedgerBytes = 64 * 1024

  let url: URL

  init(url: URL = defaultURL) {
    self.url = url.standardizedFileURL
  }

  func load() throws -> FanControlRecoveryState {
    guard let metadata = try metadataIfPresent(at: url) else {
      return FanControlRecoveryState()
    }
    try validateType(metadata, expectedType: mode_t(S_IFREG), itemIsDirectory: false)
    guard metadata.st_nlink == 1 else { throw FanControlRecoveryStoreError.invalidLedger }
    guard metadata.st_size > 0 else { throw FanControlRecoveryStoreError.invalidLedger }
    guard metadata.st_size <= Int64(Self.maximumLedgerBytes) else {
      throw FanControlRecoveryStoreError.oversizedLedger
    }
    try validateOwnerAndPermissions(metadata, requiredOwnerBits: 0o600)

    let data: Data
    do {
      data = try Data(contentsOf: url, options: [.mappedIfSafe])
    } catch {
      throw FanControlRecoveryStoreError.ioFailure(error.localizedDescription)
    }

    let document: FanControlRecoveryDocument
    do {
      document = try JSONDecoder().decode(FanControlRecoveryDocument.self, from: data)
    } catch {
      throw FanControlRecoveryStoreError.invalidLedger
    }

    guard document.schemaVersion == Self.schemaVersion,
      document.entries.count <= FanValueNormalizer.maximumFanCount
    else { throw FanControlRecoveryStoreError.invalidLedger }

    var deadlines: [Int: Date] = [:]
    for entry in document.entries {
      guard entry.fanIndex >= 0,
        entry.fanIndex < FanValueNormalizer.maximumFanCount,
        entry.deadlineEpochSeconds.isFinite,
        deadlines[entry.fanIndex] == nil
      else { throw FanControlRecoveryStoreError.invalidLedger }
      deadlines[entry.fanIndex] = Date(timeIntervalSince1970: entry.deadlineEpochSeconds)
    }
    return FanControlRecoveryState(deadlines: deadlines)
  }

  func save(_ state: FanControlRecoveryState) throws {
    try ensureSecureDirectory()
    if state.isEmpty {
      try removeLedgerIfPresent()
      return
    }

    let entries = state.deadlines.keys.sorted().compactMap { index -> FanControlRecoveryDocument.Entry? in
      guard let deadline = state.deadlines[index] else { return nil }
      return .init(fanIndex: index, deadlineEpochSeconds: deadline.timeIntervalSince1970)
    }
    guard entries.count == state.deadlines.count,
      entries.allSatisfy({
        $0.fanIndex >= 0 &&
          $0.fanIndex < FanValueNormalizer.maximumFanCount &&
          $0.deadlineEpochSeconds.isFinite
      })
    else { throw FanControlRecoveryStoreError.invalidLedger }

    let document = FanControlRecoveryDocument(
      schemaVersion: Self.schemaVersion,
      entries: entries)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data: Data
    do {
      data = try encoder.encode(document)
    } catch {
      throw FanControlRecoveryStoreError.ioFailure(error.localizedDescription)
    }
    guard !data.isEmpty, data.count <= Self.maximumLedgerBytes else {
      throw FanControlRecoveryStoreError.oversizedLedger
    }

    let directory = url.deletingLastPathComponent()
    let temporary = directory.appendingPathComponent(".fan-recovery-\(UUID().uuidString).tmp")
    defer { try? FileManager.default.removeItem(at: temporary) }

    do {
      try data.write(to: temporary, options: [])
    } catch {
      throw FanControlRecoveryStoreError.ioFailure(error.localizedDescription)
    }
    let chmodResult = temporary.path.withCString { Darwin.chmod($0, 0o600) }
    guard chmodResult == 0 else {
      throw FanControlRecoveryStoreError.ioFailure(String(cString: strerror(errno)))
    }
    let temporaryMetadata = try secureMetadata(
      at: temporary,
      expectedType: mode_t(S_IFREG),
      itemIsDirectory: false)
    guard temporaryMetadata.st_nlink == 1 else {
      throw FanControlRecoveryStoreError.invalidLedger
    }
    try validateOwnerAndPermissions(temporaryMetadata, requiredOwnerBits: 0o600)
    try syncFile(temporary)

    let renameResult = temporary.path.withCString { source in
      url.path.withCString { destination in
        Darwin.rename(source, destination)
      }
    }
    guard renameResult == 0 else {
      throw FanControlRecoveryStoreError.ioFailure(String(cString: strerror(errno)))
    }
    try syncDirectory(directory)
  }

  private func ensureSecureDirectory() throws {
    let directory = url.deletingLastPathComponent()
    if try metadataIfPresent(at: directory) == nil {
      do {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
      } catch {
        throw FanControlRecoveryStoreError.ioFailure(error.localizedDescription)
      }
      let chmodResult = directory.path.withCString { Darwin.chmod($0, 0o700) }
      guard chmodResult == 0 else {
        throw FanControlRecoveryStoreError.ioFailure(String(cString: strerror(errno)))
      }
    }

    let metadata = try secureMetadata(
      at: directory,
      expectedType: mode_t(S_IFDIR),
      itemIsDirectory: true)
    try validateOwnerAndPermissions(metadata, requiredOwnerBits: 0o700)
  }

  private func removeLedgerIfPresent() throws {
    guard let metadata = try metadataIfPresent(at: url) else { return }
    try validateType(metadata, expectedType: mode_t(S_IFREG), itemIsDirectory: false)
    guard metadata.st_nlink == 1 else { throw FanControlRecoveryStoreError.invalidLedger }
    try validateOwnerAndPermissions(metadata, requiredOwnerBits: 0o600)
    do {
      try FileManager.default.removeItem(at: url)
      try syncDirectory(url.deletingLastPathComponent())
    } catch let error as FanControlRecoveryStoreError {
      throw error
    } catch {
      throw FanControlRecoveryStoreError.ioFailure(error.localizedDescription)
    }
  }

  private func metadataIfPresent(at itemURL: URL) throws -> stat? {
    var metadata = stat()
    let result = itemURL.path.withCString { lstat($0, &metadata) }
    if result == 0 { return metadata }
    if errno == ENOENT { return nil }
    throw FanControlRecoveryStoreError.ioFailure(String(cString: strerror(errno)))
  }

  private func secureMetadata(
    at itemURL: URL,
    expectedType: mode_t,
    itemIsDirectory: Bool
  ) throws -> stat {
    guard let metadata = try metadataIfPresent(at: itemURL) else {
      throw FanControlRecoveryStoreError.ioFailure("Required path does not exist")
    }
    try validateType(
      metadata,
      expectedType: expectedType,
      itemIsDirectory: itemIsDirectory)
    return metadata
  }

  private func validateType(
    _ metadata: stat,
    expectedType: mode_t,
    itemIsDirectory: Bool
  ) throws {
    guard (metadata.st_mode & mode_t(S_IFMT)) == expectedType else {
      throw itemIsDirectory
        ? FanControlRecoveryStoreError.invalidDirectory
        : FanControlRecoveryStoreError.invalidLedger
    }
  }

  private func validateOwnerAndPermissions(_ metadata: stat, requiredOwnerBits: mode_t) throws {
    guard metadata.st_uid == geteuid() else {
      throw FanControlRecoveryStoreError.unsafeOwnership
    }
    let permissions = metadata.st_mode & 0o777
    guard permissions & 0o077 == 0,
      permissions & requiredOwnerBits == requiredOwnerBits
    else { throw FanControlRecoveryStoreError.unsafePermissions }
  }

  private func syncFile(_ file: URL) throws {
    let descriptor = file.path.withCString { Darwin.open($0, O_RDONLY) }
    guard descriptor >= 0 else {
      throw FanControlRecoveryStoreError.ioFailure(String(cString: strerror(errno)))
    }
    defer { _ = Darwin.close(descriptor) }
    guard fsync(descriptor) == 0 else {
      throw FanControlRecoveryStoreError.ioFailure(String(cString: strerror(errno)))
    }
  }

  private func syncDirectory(_ directory: URL) throws {
    let descriptor = directory.path.withCString { Darwin.open($0, O_RDONLY) }
    guard descriptor >= 0 else {
      throw FanControlRecoveryStoreError.ioFailure(String(cString: strerror(errno)))
    }
    defer { _ = Darwin.close(descriptor) }
    guard fsync(descriptor) == 0 else {
      throw FanControlRecoveryStoreError.ioFailure(String(cString: strerror(errno)))
    }
  }
}
