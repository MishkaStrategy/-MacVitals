import XCTest

@testable import MacVitals

final class FanControlClientStateTests: XCTestCase {
  func testOnlyReadyStateCanControlFans() {
    XCTAssertTrue(FanControlClientState.ready.canControl)

    let passiveStates: [FanControlClientState] = [
      .monitoringOnly,
      .notRegistered,
      .approvalRequired,
      .connecting,
      .unavailable("offline"),
    ]
    for state in passiveStates {
      XCTAssertFalse(state.canControl, "Unexpected control permission for \(state)")
    }
  }
}
