import Darwin
import XCTest

@testable import MacVitals

final class FanControlRecoveryStoreTests: XCTestCase {
  func testRoundTripPersistsActiveAndImmediateRecoveryWithPrivatePermissions() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var state = FanControlRecoveryState()
    state.beginRecovery(index: 0, now: now)
    state.activate(index: 1, deadline: now.addingTimeInterval(600))

    try fixture.store.save(state)
    XCTAssertEqual(try fixture.store.load(), state)

    let attributes = try FileManager.default.attributesOfItem(atPath: fixture.ledger.path)
    let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    XCTAssertEqual(permissions & 0o777, 0o600)
  }

  func testSavingEmptyStateRemovesLedger() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }

    var state = FanControlRecoveryState()
    state.activate(index: 0, deadline: Date().addingTimeInterval(300))
    try fixture.store.save(state)
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.ledger.path))

    try fixture.store.save(FanControlRecoveryState())
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.ledger.path))
    XCTAssertTrue(try fixture.store.load().isEmpty)
  }

  func testSymlinkAndDanglingSymlinkLedgersFailClosed() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }

    var state = FanControlRecoveryState()
    state.activate(index: 0, deadline: Date().addingTimeInterval(300))
    try fixture.store.save(state)
    try FileManager.default.removeItem(at: fixture.ledger)

    let target = fixture.root.appendingPathComponent("attacker.json")
    try Data("{}".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(
      at: fixture.ledger,
      withDestinationURL: target)
    XCTAssertThrowsError(try fixture.store.load())

    try FileManager.default.removeItem(at: fixture.ledger)
    try FileManager.default.removeItem(at: target)
    try FileManager.default.createSymbolicLink(
      at: fixture.ledger,
      withDestinationURL: target)
    XCTAssertThrowsError(try fixture.store.load())
  }

  func testGroupOrWorldReadableLedgerFailsClosed() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }

    var state = FanControlRecoveryState()
    state.activate(index: 0, deadline: Date().addingTimeInterval(300))
    try fixture.store.save(state)
    let chmodResult = fixture.ledger.path.withCString { Darwin.chmod($0, 0o644) }
    XCTAssertEqual(chmodResult, 0)

    XCTAssertThrowsError(try fixture.store.load())
  }

  func testInvalidIndexesAndDuplicateEntriesFailClosed() throws {
    let fixture = try makeFixture()
    defer { fixture.cleanup() }
    try FileManager.default.createDirectory(
      at: fixture.ledger.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])

    let invalidDocuments = [
      "{\"entries\":[{\"deadlineEpochSeconds\":1800000000,\"fanIndex\":8}],\"schemaVersion\":1}",
      "{\"entries\":[{\"deadlineEpochSeconds\":1800000000,\"fanIndex\":0},{\"deadlineEpochSeconds\":1800000300,\"fanIndex\":0}],\"schemaVersion\":1}",
      "{\"entries\":[],\"schemaVersion\":2}",
    ]

    for document in invalidDocuments {
      try Data(document.utf8).write(to: fixture.ledger, options: [.atomic])
      let chmodResult = fixture.ledger.path.withCString { Darwin.chmod($0, 0o600) }
      XCTAssertEqual(chmodResult, 0)
      XCTAssertThrowsError(try fixture.store.load())
    }
  }

  func testPendingRecoveryDistinguishesExpiredFromActiveLease() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var state = FanControlRecoveryState()
    state.activate(index: 0, deadline: now.addingTimeInterval(300))
    XCTAssertFalse(state.hasPendingRecovery(at: now))

    state.beginRecovery(index: 1, now: now)
    XCTAssertTrue(state.hasPendingRecovery(at: now))
    XCTAssertEqual(state.expired(at: now), [1])
  }

  private func makeFixture() throws -> Fixture {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MacVitalsFanRecoveryTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    let ledger = root
      .appendingPathComponent("private", isDirectory: true)
      .appendingPathComponent("fan-control-recovery-v1.json", isDirectory: false)
    return Fixture(
      root: root,
      ledger: ledger,
      store: FanControlRecoveryStore(url: ledger))
  }
}

private struct Fixture {
  let root: URL
  let ledger: URL
  let store: FanControlRecoveryStore

  func cleanup() {
    try? FileManager.default.removeItem(at: root)
  }
}
