import AppKit
import XCTest
@testable import MacVitals

final class NotchHUDLayoutTests: XCTestCase {
  func testRailFrameStaysCompactAndCentered() {
    let screen = NSRect(x: 0, y: 0, width: 1_728, height: 1_117)
    let frame = NotchHUDLayout.railFrame(for: screen, safeAreaTop: 38)

    XCTAssertEqual(frame.height, 38)
    XCTAssertLessThanOrEqual(frame.width, 1_240)
    XCTAssertGreaterThanOrEqual(frame.minX, screen.minX)
    XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)
    XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
    XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.5)
  }

  func testDetailPanelIsCenteredImmediatelyBelowRail() {
    let screen = NSRect(x: 0, y: 0, width: 1_728, height: 1_117)
    let rail = NotchHUDLayout.railFrame(for: screen, safeAreaTop: 38)
    let detail = NotchHUDLayout.detailFrame(below: rail, screenFrame: screen)

    XCTAssertEqual(detail.size, NotchHUDLayout.detailSize)
    XCTAssertEqual(detail.midX, rail.midX, accuracy: 0.5)
    XCTAssertEqual(
      rail.minY - detail.maxY,
      NotchHUDLayout.detailGap,
      accuracy: 0.5)
  }

  func testSmallExternalDisplayFallbackRemainsOnScreen() {
    let screen = NSRect(x: 320, y: 100, width: 700, height: 500)
    let rail = NotchHUDLayout.railFrame(for: screen, safeAreaTop: 0)
    let detail = NotchHUDLayout.detailFrame(below: rail, screenFrame: screen)

    XCTAssertGreaterThanOrEqual(rail.minX, screen.minX)
    XCTAssertLessThanOrEqual(rail.maxX, screen.maxX)
    XCTAssertGreaterThanOrEqual(detail.minX, screen.minX)
    XCTAssertLessThanOrEqual(detail.maxX, screen.maxX)
    XCTAssertGreaterThanOrEqual(detail.minY, screen.minY)
  }
}
