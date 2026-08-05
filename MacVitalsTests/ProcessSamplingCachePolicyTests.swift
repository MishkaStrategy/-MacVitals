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

  func testCurrentRequestWithSubscribersCommitsResult() {
    let requestID = UUID()

    XCTAssertEqual(
      ProcessSamplingCachePolicy.resultDisposition(
        requestID: requestID,
        activeRequestID: requestID,
        hasSubscribers: true),
      .commit)
  }

  func testCurrentRequestWithoutSubscribersOnlyClearsInFlightState() {
    let requestID = UUID()

    XCTAssertEqual(
      ProcessSamplingCachePolicy.resultDisposition(
        requestID: requestID,
        activeRequestID: requestID,
        hasSubscribers: false),
      .clearOnly)
  }

  func testStaleRequestCannotMutateCurrentState() {
    XCTAssertEqual(
      ProcessSamplingCachePolicy.resultDisposition(
        requestID: UUID(),
        activeRequestID: UUID(),
        hasSubscribers: true),
      .ignore)
  }

  func testCompletedRequestIsIgnoredAfterInFlightStateWasCleared() {
    XCTAssertEqual(
      ProcessSamplingCachePolicy.resultDisposition(
        requestID: UUID(),
        activeRequestID: nil,
        hasSubscribers: false),
      .ignore)
  }
}
