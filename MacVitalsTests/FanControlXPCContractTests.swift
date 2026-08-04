import Foundation
import XCTest

@testable import MacVitals

final class FanControlXPCContractTests: XCTestCase {
  func testServiceConstantsMatchApprovedIdentifiers() {
    XCTAssertEqual(
      FanControlServiceConstants.machServiceName,
      FanControlSigningPolicy.helperIdentifier)
    XCTAssertEqual(
      FanControlServiceConstants.daemonPlistName,
      "\(FanControlSigningPolicy.helperIdentifier).plist")
    XCTAssertEqual(FanControlServiceConstants.helperExecutableName, "MacVitalsFanHelper")
  }

  func testXPCInterfaceCanBeMaterialized() {
    let interface = NSXPCInterface(with: FanControlXPCProtocol.self)
    XCTAssertNotNil(interface)
  }

  func testOnlyReadyStateAllowsPhysicalControl() {
    let states: [FanControlClientState] = [
      .monitoringOnly,
      .notRegistered,
      .approvalRequired,
      .connecting,
      .unavailable("test"),
    ]

    XCTAssertTrue(states.allSatisfy { !$0.canControl })
    XCTAssertTrue(FanControlClientState.ready.canControl)
  }

  func testServiceIdentifiersAreMachServiceSafe() {
    let identifiers = [
      FanControlServiceConstants.machServiceName,
      FanControlSigningPolicy.mainApplicationIdentifier,
      FanControlSigningPolicy.helperIdentifier,
    ]

    for identifier in identifiers {
      XCTAssertFalse(identifier.isEmpty)
      XCTAssertFalse(identifier.contains("/"))
      XCTAssertFalse(identifier.contains("\\"))
      XCTAssertFalse(identifier.contains(".."))
      XCTAssertTrue(identifier.allSatisfy {
        $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-")
      })
    }
  }
}
