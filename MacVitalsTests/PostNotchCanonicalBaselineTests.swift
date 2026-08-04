import AppKit
import XCTest
@testable import MacVitals

final class PostNotchCanonicalBaselineTests: XCTestCase {
  func testAcceptedPhysicalMacBookReferenceGeometry() throws {
    let screen = NSRect(x: 0, y: 0, width: 2_056, height: 1_329)
    let hardware = try XCTUnwrap(NotchHUDLayout.hardwareNotchGeometry(
      screenFrame: screen,
      safeAreaTop: 38,
      auxiliaryTopLeftArea: NSRect(x: 0, y: 1_291, width: 918, height: 38),
      auxiliaryTopRightArea: NSRect(x: 1_138, y: 1_291, width: 918, height: 38)))

    XCTAssertEqual(hardware.width, 220, accuracy: 0.001)
    XCTAssertEqual(hardware.centerX, 1_028, accuracy: 0.001)

    var configuration = NotchHUDConfiguration.minimal
    configuration.horizontalExtension = 72
    configuration.showValueText = true

    let frame = NotchHUDLayout.panelFrame(
      for: screen,
      safeAreaTop: 38,
      configuration: configuration,
      notchGeometry: hardware)

    XCTAssertEqual(frame.minX, 846, accuracy: 0.001)
    XCTAssertEqual(frame.width, 364, accuracy: 0.001)
    XCTAssertEqual(frame.height, 70, accuracy: 0.001)
    XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.001)
  }

  func testVisibleStrokeEdgeTouchesAcceptedHardwareSafeArea() {
    let lineThickness: CGFloat = 2.5
    let panelWidth: CGFloat = 364
    let hardwareNotchWidth: CGFloat = 220
    let geometry = NotchHUDLayout.contourGeometry(
      in: CGSize(width: panelWidth, height: 70),
      safeAreaTop: 38,
      lineThickness: lineThickness,
      notchWidth: hardwareNotchWidth)

    let halfLine = lineThickness / 2
    let hardwareLeft = (panelWidth - hardwareNotchWidth) / 2
    let hardwareRight = hardwareLeft + hardwareNotchWidth

    XCTAssertEqual(geometry.bottomY - halfLine, 38, accuracy: 0.001)
    XCTAssertEqual(geometry.notchLeftX + halfLine, hardwareLeft, accuracy: 0.001)
    XCTAssertEqual(geometry.notchRightX - halfLine, hardwareRight, accuracy: 0.001)
    XCTAssertEqual(NotchHUDLayout.minimumContourClearance, 0, accuracy: 0.001)
  }
}
