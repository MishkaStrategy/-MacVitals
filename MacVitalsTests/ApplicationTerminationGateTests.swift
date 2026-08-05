import XCTest

@testable import MacVitals

@MainActor
final class ApplicationTerminationGateTests: XCTestCase {
  func testOnlyReadyFanStateDelaysTermination() {
    XCTAssertTrue(FanTerminationPolicy.shouldDelayTermination(for: .ready))

    let immediateStates: [FanControlClientState] = [
      .monitoringOnly,
      .notRegistered,
      .approvalRequired,
      .connecting,
      .unavailable("offline"),
    ]
    for state in immediateStates {
      XCTAssertFalse(FanTerminationPolicy.shouldDelayTermination(for: state))
    }
  }

  func testTerminationGateBeginsOnlyOnceUntilCompletion() {
    let gate = ApplicationTerminationGate()

    XCTAssertTrue(gate.begin())
    XCTAssertFalse(gate.begin())
    XCTAssertTrue(gate.isPending)

    var completionCount = 0
    gate.complete { completionCount += 1 }
    gate.complete { completionCount += 1 }

    XCTAssertEqual(completionCount, 1)
    XCTAssertFalse(gate.isPending)
    XCTAssertTrue(gate.begin())
  }

  func testCancelDropsPendingCompletion() {
    let gate = ApplicationTerminationGate()
    XCTAssertTrue(gate.begin())

    gate.cancel()
    var completionCount = 0
    gate.complete { completionCount += 1 }

    XCTAssertEqual(completionCount, 0)
    XCTAssertFalse(gate.isPending)
  }

  func testRestoreTimeoutIsBounded() {
    XCTAssertEqual(FanTerminationPolicy.restoreTimeoutNanoseconds, 2_000_000_000)
  }
}
