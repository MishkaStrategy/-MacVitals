import AppKit
import XCTest
@testable import MacVitals

final class NotchHUDLayoutTests: XCTestCase {
  func testSidePanelsHugNotchInsideMenuBarHeight() {
    let screen = NSRect(x: 0, y: 0, width: 1_728, height: 1_117)
    let frames = NotchHUDLayout.sideFrames(for: screen, safeAreaTop: 38)

    XCTAssertEqual(frames.left.height, NotchHUDLayout.panelHeight)
    XCTAssertEqual(frames.right.height, NotchHUDLayout.panelHeight)
    XCTAssertEqual(frames.left.minY, frames.right.minY, accuracy: 0.5)
    XCTAssertGreaterThanOrEqual(frames.left.minY, screen.maxY - 40)
    XCTAssertLessThanOrEqual(frames.left.maxY, screen.maxY)
    XCTAssertLessThan(frames.left.maxX, screen.midX)
    XCTAssertGreaterThan(frames.right.minX, screen.midX)
    XCTAssertEqual(
      screen.midX - frames.left.maxX,
      NotchHUDLayout.notchHalfWidth + NotchHUDLayout.notchGap,
      accuracy: 0.5)
    XCTAssertEqual(
      frames.right.minX - screen.midX,
      NotchHUDLayout.notchHalfWidth + NotchHUDLayout.notchGap,
      accuracy: 0.5)
  }

  func testLayoutContainsOnlyOneCompactPanelPerSide() {
    let screen = NSRect(x: 0, y: 0, width: 1_728, height: 1_117)
    let frames = NotchHUDLayout.sideFrames(for: screen, safeAreaTop: 38)

    XCTAssertEqual(frames.left.width, NotchHUDLayout.leftPanelWidth)
    XCTAssertEqual(frames.right.width, NotchHUDLayout.rightPanelWidth)
    XCTAssertFalse(frames.left.intersects(frames.right))
    XCTAssertLessThanOrEqual(frames.left.maxX, screen.midX - NotchHUDLayout.notchHalfWidth)
    XCTAssertGreaterThanOrEqual(frames.right.minX, screen.midX + NotchHUDLayout.notchHalfWidth)
  }

  func testSmallExternalDisplayFallbackRemainsOnScreen() {
    let screen = NSRect(x: 320, y: 100, width: 700, height: 500)
    let frames = NotchHUDLayout.sideFrames(for: screen, safeAreaTop: 0)

    XCTAssertGreaterThanOrEqual(frames.left.minX, screen.minX)
    XCTAssertLessThanOrEqual(frames.left.maxX, screen.maxX)
    XCTAssertGreaterThanOrEqual(frames.right.minX, screen.minX)
    XCTAssertLessThanOrEqual(frames.right.maxX, screen.maxX)
    XCTAssertGreaterThanOrEqual(frames.left.minY, screen.minY)
    XCTAssertLessThanOrEqual(frames.right.maxY, screen.maxY)
    XCTAssertFalse(frames.left.intersects(frames.right))
  }

  @MainActor
  func testDisabledHUDDoesNotAllocateAppKitPanelsDuringSampling() {
    let controller = NotchHUDController()

    XCTAssertFalse(controller.hasAllocatedPanelsForTesting)
    controller.update(snapshot: .empty, preferredScreen: nil, enabled: false)
    XCTAssertFalse(controller.hasAllocatedPanelsForTesting)
  }
}
