import Foundation
import XCTest

@testable import MacVitals

final class SmartBatteryRegistryCacheTests: XCTestCase {
  func testAdjacentReadsReuseOneRegistrySnapshot() {
    let counter = LockedCounter()
    let cache = SmartBatteryRegistryCache(freshnessInterval: 0.25) {
      ["generation": counter.increment()]
    }

    let first = cache.snapshot(now: 10)
    let second = cache.snapshot(now: 10.2)

    XCTAssertEqual(first["generation"] as? Int, 1)
    XCTAssertEqual(second["generation"] as? Int, 1)
    XCTAssertEqual(counter.value, 1)
  }

  func testSnapshotRefreshesAtWindowBoundary() {
    let counter = LockedCounter()
    let cache = SmartBatteryRegistryCache(freshnessInterval: 0.25) {
      ["generation": counter.increment()]
    }

    _ = cache.snapshot(now: 10)
    let refreshed = cache.snapshot(now: 10.25)

    XCTAssertEqual(refreshed["generation"] as? Int, 2)
    XCTAssertEqual(counter.value, 2)
  }

  func testClockRollbackFailsClosedByRefreshing() {
    let counter = LockedCounter()
    let cache = SmartBatteryRegistryCache(freshnessInterval: 10) {
      ["generation": counter.increment()]
    }

    _ = cache.snapshot(now: 10)
    let refreshed = cache.snapshot(now: 9)

    XCTAssertEqual(refreshed["generation"] as? Int, 2)
    XCTAssertEqual(counter.value, 2)
  }

  func testResetForcesNextPhysicalRead() {
    let counter = LockedCounter()
    let cache = SmartBatteryRegistryCache(freshnessInterval: 10) {
      ["generation": counter.increment()]
    }

    _ = cache.snapshot(now: 10)
    cache.reset()
    let refreshed = cache.snapshot(now: 10.1)

    XCTAssertEqual(refreshed["generation"] as? Int, 2)
    XCTAssertEqual(counter.value, 2)
  }
}

private final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = 0

  var value: Int {
    lock.withLock { storage }
  }

  func increment() -> Int {
    lock.withLock {
      storage += 1
      return storage
    }
  }
}
