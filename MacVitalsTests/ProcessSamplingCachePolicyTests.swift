import XCTest
@testable import MacVitals

final class ProcessSamplingCachePolicyTests: XCTestCase {
  func testFreshSnapshotIsReusableInsideWindow() {
    let now = Date(timeIntervalSince1970: 1_000)
    XCTAssertTrue(
      ProcessSamplingCachePolicy.isFresh(
        timestamp: now.addingTimeInterval(-1),
        now: now,
        minimumInterval: 2))
  }

  func testSnapshotExpiresOutsideWindow() {
    let now = Date(timeIntervalSince1970: 1_000)
    XCTAssertFalse(
      ProcessSamplingCachePolicy.isFresh(
        timestamp: now.addingTimeInterval(-2),
        now: now,
        minimumInterval: 2))
  }

  func testEmptySnapshotIsNeverFresh() {
    XCTAssertFalse(
      ProcessSamplingCachePolicy.isFresh(
        timestamp: .distantPast,
        now: Date(),
        minimumInterval: 30))
  }

  func testFreshnessWindowHasSafeLowerBound() {
    XCTAssertEqual(ProcessSamplingCachePolicy.freshnessWindow(minimumInterval: 0), 0.25)
    XCTAssertEqual(ProcessSamplingCachePolicy.freshnessWindow(minimumInterval: 10), 8)
  }
}
