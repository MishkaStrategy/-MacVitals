import AppKit
import XCTest
@testable import MacVitals

final class NotchHUDLayoutTests: XCTestCase {
  func testSidePanelsHugNotchInsideMenuBarHeight() {
    let screen = NSRect(x: 0, y: 0, width: 1_728, height: 1_117)
    let configuration = NotchHUDConfiguration.balanced
    let frames = NotchHUDLayout.sideFrames(
      for: screen,
      safeAreaTop: 38,
      configuration: configuration)

    XCTAssertEqual(frames.left.height, CGFloat(configuration.density.panelHeight))
    XCTAssertEqual(frames.right.height, CGFloat(configuration.density.panelHeight))
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

  func testPanelWidthsFollowVisibleSensorCounts() {
    let screen = NSRect(x: 0, y: 0, width: 1_728, height: 1_117)
    var configuration = NotchHUDConfiguration.balanced
    configuration.leftVisibleCount = 1
    configuration.rightVisibleCount = 2
    let frames = NotchHUDLayout.sideFrames(
      for: screen,
      safeAreaTop: 38,
      configuration: configuration)

    XCTAssertEqual(
      frames.left.width,
      NotchHUDLayout.preferredPanelWidth(
        metricCount: 1,
        configuration: configuration),
      accuracy: 0.5)
    XCTAssertEqual(
      frames.right.width,
      NotchHUDLayout.preferredPanelWidth(
        metricCount: 2,
        configuration: configuration),
      accuracy: 0.5)
    XCTAssertFalse(frames.left.intersects(frames.right))
  }

  func testDetailedPresetFitsOnNotchedMacBookScreen() {
    let screen = NSRect(x: 0, y: 0, width: 1_728, height: 1_117)
    let configuration = NotchHUDConfiguration.detailed
    let frames = NotchHUDLayout.sideFrames(
      for: screen,
      safeAreaTop: 38,
      configuration: configuration)

    XCTAssertGreaterThan(frames.left.width, NotchHUDLayout.minimumPanelWidth)
    XCTAssertGreaterThan(frames.right.width, frames.left.width)
    XCTAssertLessThanOrEqual(frames.left.maxX, screen.midX - NotchHUDLayout.notchHalfWidth)
    XCTAssertGreaterThanOrEqual(frames.right.minX, screen.midX + NotchHUDLayout.notchHalfWidth)
    XCTAssertGreaterThanOrEqual(frames.left.minX, screen.minX + NotchHUDLayout.edgeMargin)
    XCTAssertLessThanOrEqual(frames.right.maxX, screen.maxX - NotchHUDLayout.edgeMargin)
  }

  func testSmallExternalDisplayFallbackRemainsOnScreen() {
    let screen = NSRect(x: 320, y: 100, width: 700, height: 500)
    let frames = NotchHUDLayout.sideFrames(
      for: screen,
      safeAreaTop: 0,
      configuration: .detailed)

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
