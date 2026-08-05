import Foundation
import XCTest

@testable import MacVitals

final class SamplingActivityLeaseTests: XCTestCase {
  func testStartAndStopAreIdempotent() {
    let recorder = ActivityRecorder()
    let lease = makeLease(recorder: recorder)

    lease.start()
    lease.start()
    XCTAssertEqual(recorder.beginCount, 1)
    XCTAssertEqual(recorder.endCount, 0)

    lease.stop()
    lease.stop()
    XCTAssertEqual(recorder.beginCount, 1)
    XCTAssertEqual(recorder.endCount, 1)
  }

  func testLeaseCanRestartAfterStop() {
    let recorder = ActivityRecorder()
    let lease = makeLease(recorder: recorder)

    lease.start()
    lease.stop()
    lease.start()
    lease.stop()

    XCTAssertEqual(recorder.beginCount, 2)
    XCTAssertEqual(recorder.endCount, 2)
  }

  func testDeinitEndsActiveActivityExactlyOnce() {
    let recorder = ActivityRecorder()
    var lease: SamplingActivityLease? = makeLease(recorder: recorder)

    lease?.start()
    lease = nil

    XCTAssertEqual(recorder.beginCount, 1)
    XCTAssertEqual(recorder.endCount, 1)
  }

  private func makeLease(recorder: ActivityRecorder) -> SamplingActivityLease {
    SamplingActivityLease(
      beginActivity: { recorder.begin() },
      endActivity: { recorder.end($0) })
  }
}

private final class ActivityToken: NSObject {}

private final class ActivityRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var begins = 0
  private var ends = 0

  var beginCount: Int {
    lock.withLock { begins }
  }

  var endCount: Int {
    lock.withLock { ends }
  }

  func begin() -> any NSObjectProtocol {
    lock.withLock { begins += 1 }
    return ActivityToken()
  }

  func end(_ token: any NSObjectProtocol) {
    _ = token
    lock.withLock { ends += 1 }
  }
}
