import AppKit
import XCTest
@testable import MacVitals

final class NotchHUDIndicatorTests: XCTestCase {
  func testPanelFrameIsCenteredOnNotch() {
    var configuration = NotchHUDConfiguration.minimal
    configuration.horizontalExtension = 80

    let screen = NSRect(x: 0, y: 0, width: 1_512, height: 982)
    let frame = NotchHUDLayout.panelFrame(
      for: screen,
      safeAreaTop: 38,
      configuration: configuration)

    XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
    XCTAssertEqual(frame.width, 372, accuracy: 0.001)
    XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.001)
  }

  func testHardwareNotchGeometryUsesAuxiliaryTopAreas() throws {
    let screen = NSRect(x: 0, y: 0, width: 2_056, height: 1_329)
    let geometry = try XCTUnwrap(NotchHUDLayout.hardwareNotchGeometry(
      screenFrame: screen,
      safeAreaTop: 38,
      auxiliaryTopLeftArea: NSRect(x: 0, y: 1_291, width: 922, height: 38),
      auxiliaryTopRightArea: NSRect(x: 1_134, y: 1_291, width: 922, height: 38)))

    XCTAssertEqual(geometry.width, 212, accuracy: 0.001)
    XCTAssertEqual(geometry.centerX, 1_028, accuracy: 0.001)
  }

  func testPanelFrameUsesDetectedNotchCenterAndWidth() {
    var configuration = NotchHUDConfiguration.minimal
    configuration.horizontalExtension = 80

    let screen = NSRect(x: 100, y: 0, width: 1_600, height: 1_000)
    let hardware = NotchHUDHardwareGeometry(centerX: 860, width: 220)
    let frame = NotchHUDLayout.panelFrame(
      for: screen,
      safeAreaTop: 38,
      configuration: configuration,
      notchGeometry: hardware)

    XCTAssertEqual(frame.midX, hardware.centerX, accuracy: 0.001)
    XCTAssertEqual(frame.width, 380, accuracy: 0.001)
    XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.001)
  }

  func testPanelFrameStaysOnSmallOffsetDisplay() {
    var configuration = NotchHUDConfiguration.minimal
    configuration.horizontalExtension = 180

    let screen = NSRect(x: -900, y: 200, width: 500, height: 700)
    let hardware = NotchHUDHardwareGeometry(centerX: -470, width: 230)
    let frame = NotchHUDLayout.panelFrame(
      for: screen,
      safeAreaTop: 52,
      configuration: configuration,
      notchGeometry: hardware)

    XCTAssertGreaterThanOrEqual(frame.minX, screen.minX + NotchHUDLayout.edgeMargin)
    XCTAssertLessThanOrEqual(frame.maxX, screen.maxX - NotchHUDLayout.edgeMargin)
    XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.001)
  }

  func testHardwareNotchGeometryRejectsMissingSafeArea() {
    XCTAssertNil(NotchHUDLayout.hardwareNotchGeometry(
      screenFrame: NSRect(x: 0, y: 0, width: 1_512, height: 982),
      safeAreaTop: 0,
      auxiliaryTopLeftArea: NSRect(x: 0, y: 950, width: 650, height: 32),
      auxiliaryTopRightArea: NSRect(x: 862, y: 950, width: 650, height: 32)))
  }

  func testSafeAreaHeightUsesLiveDisplayValueWithoutModelClamp() {
    XCTAssertEqual(NotchHUDLayout.resolvedSafeAreaTop(27), 27, accuracy: 0.001)
    XCTAssertEqual(NotchHUDLayout.resolvedSafeAreaTop(52), 52, accuracy: 0.001)
    XCTAssertEqual(
      NotchHUDLayout.resolvedSafeAreaTop(.nan),
      NotchHUDLayout.minimumSafeAreaTop,
      accuracy: 0.001)
    XCTAssertEqual(
      NotchHUDLayout.resolvedSafeAreaTop(0),
      NotchHUDLayout.minimumSafeAreaTop,
      accuracy: 0.001)
  }

  func testBackingRectIsAlignedOutwardForFractionalScaledCoordinates() {
    let aligned = NotchHUDLayout.outwardIntegralBackingRect(
      NSRect(x: 1_843.25, y: 2_581.5, width: 439.5, height: 76.25))

    XCTAssertEqual(aligned.minX, 1_843, accuracy: 0.001)
    XCTAssertEqual(aligned.minY, 2_581, accuracy: 0.001)
    XCTAssertEqual(aligned.maxX, 2_283, accuracy: 0.001)
    XCTAssertEqual(aligned.maxY, 2_658, accuracy: 0.001)
  }

  func testContourGeometryTouchesHardwareCutoutExactly() {
    let lineThickness: CGFloat = 6
    let panelWidth: CGFloat = 356
    let hardwareNotchWidth: CGFloat = 212
    let geometry = NotchHUDLayout.contourGeometry(
      in: CGSize(width: panelWidth, height: 70),
      safeAreaTop: 38,
      lineThickness: lineThickness,
      notchWidth: hardwareNotchWidth)
    let hardwareLeft = (panelWidth - hardwareNotchWidth) / 2
    let hardwareRight = hardwareLeft + hardwareNotchWidth
    let halfLine = lineThickness / 2

    XCTAssertLessThanOrEqual(geometry.topY, 1)
    XCTAssertEqual(geometry.notchLeftX + halfLine, hardwareLeft, accuracy: 0.001)
    XCTAssertEqual(geometry.notchRightX - halfLine, hardwareRight, accuracy: 0.001)
    XCTAssertEqual(geometry.bottomY - halfLine, 38, accuracy: 0.001)
    XCTAssertEqual(NotchHUDLayout.minimumContourClearance, 0, accuracy: 0.001)
    XCTAssertGreaterThan(geometry.shoulderRadius, 7)
    XCTAssertLessThanOrEqual(geometry.shoulderRadius, 16)
  }

  func testHardwareCutoutMaskMatchesForbiddenCameraArea() {
    let size = CGSize(width: 364, height: 70)
    let lineThickness: CGFloat = 2.5
    let geometry = NotchHUDLayout.contourGeometry(
      in: size,
      safeAreaTop: 38,
      lineThickness: lineThickness,
      notchWidth: 220)
    let cutout = NotchHUDLayout.hardwareCutoutRect(
      in: size,
      contourGeometry: geometry,
      lineThickness: lineThickness)

    XCTAssertEqual(cutout.minX, 72, accuracy: 0.001)
    XCTAssertEqual(cutout.width, 220, accuracy: 0.001)
    XCTAssertEqual(cutout.minY, 0, accuracy: 0.001)
    XCTAssertEqual(cutout.height, 38, accuracy: 0.001)
  }

  func testContourTracksDifferentNotchSizesAndStrokeWidths() {
    let cases: [(panel: CGSize, safeTop: CGFloat, notch: CGFloat, line: CGFloat)] = [
      (CGSize(width: 300, height: 62), 32, 180, 1),
      (CGSize(width: 364, height: 70), 38, 220, 2.5),
      (CGSize(width: 430, height: 86), 52, 250, 6),
    ]

    for item in cases {
      let geometry = NotchHUDLayout.contourGeometry(
        in: item.panel,
        safeAreaTop: item.safeTop,
        lineThickness: item.line,
        notchWidth: item.notch)
      let halfLine = min(max(item.line, 1), NotchHUDLayout.maximumIndicatorLineThickness) / 2
      let hardwareLeft = (item.panel.width - item.notch) / 2
      let hardwareRight = hardwareLeft + item.notch
      let cutout = NotchHUDLayout.hardwareCutoutRect(
        in: item.panel,
        contourGeometry: geometry,
        lineThickness: item.line)

      XCTAssertEqual(geometry.notchLeftX + halfLine, hardwareLeft, accuracy: 0.001)
      XCTAssertEqual(geometry.notchRightX - halfLine, hardwareRight, accuracy: 0.001)
      XCTAssertEqual(geometry.bottomY - halfLine, item.safeTop, accuracy: 0.001)
      XCTAssertEqual(cutout.minX, hardwareLeft, accuracy: 0.001)
      XCTAssertEqual(cutout.width, item.notch, accuracy: 0.001)
      XCTAssertEqual(cutout.height, item.safeTop, accuracy: 0.001)
      XCTAssertGreaterThan(geometry.shoulderRadius, 0)
    }
  }

  func testPanelKeepsGlowPaddingWhenLabelsAreHidden() {
    var configuration = NotchHUDConfiguration.minimal
    configuration.showValueText = false

    XCTAssertEqual(
      NotchHUDLayout.preferredPanelHeight(
        safeAreaTop: 38,
        configuration: configuration),
      58,
      accuracy: 0.001)
  }

  func testPanelHeightAdaptsToFutureSafeAreaHeight() {
    var configuration = NotchHUDConfiguration.minimal
    configuration.showValueText = true
    XCTAssertEqual(
      NotchHUDLayout.preferredPanelHeight(
        safeAreaTop: 52,
        configuration: configuration),
      84,
      accuracy: 0.001)

    configuration.showValueText = false
    XCTAssertEqual(
      NotchHUDLayout.preferredPanelHeight(
        safeAreaTop: 52,
        configuration: configuration),
      72,
      accuracy: 0.001)
  }

  func testEmptySnapshotProducesUnavailableReading() {
    let reading = NotchHUDReadingResolver.resolve(
      snapshot: .empty,
      configuration: .minimal)

    XCTAssertNil(reading.numericValue)
    XCTAssertEqual(reading.displayValue, "—")
    XCTAssertEqual(reading.progress, 0)
    XCTAssertEqual(reading.level, .unavailable)
  }

  func testSingleIndicatorKeepsFullContourProgress() {
    let segment = NotchHUDIndicatorSegments.primary(progress: 0.72, count: .one)

    XCTAssertEqual(segment.from, 0, accuracy: 0.0001)
    XCTAssertEqual(segment.to, 0.72, accuracy: 0.0001)
    XCTAssertEqual(
      NotchHUDIndicatorSegments.primaryTrack(count: .one),
      NotchHUDIndicatorSegmentRange(from: 0, to: 1))
  }

  func testTwoIndicatorsUseIndependentNonOverlappingHalves() {
    let left = NotchHUDIndicatorSegments.primary(progress: 0.72, count: .two)
    let right = NotchHUDIndicatorSegments.secondary(progress: 0.84)
    let leftTrack = NotchHUDIndicatorSegments.primaryTrack(count: .two)
    let rightTrack = NotchHUDIndicatorSegments.secondaryTrack

    XCTAssertLessThan(left.from, left.to)
    XCTAssertLessThan(left.to, 0.5)
    XCTAssertGreaterThan(right.to, right.from)
    XCTAssertGreaterThan(right.from, 0.5)
    XCTAssertLessThan(leftTrack.to, rightTrack.from)
    XCTAssertGreaterThan(left.to - left.from, 0.34)
    XCTAssertGreaterThan(right.to - right.from, 0.40)
  }

  func testPersistenceRoundTripKeepsTwoIndicatorsAndLabelsSetting() throws {
    var configuration = NotchHUDConfiguration.configuration(for: .battery)
    configuration = NotchHUDConfigurationPolicy.settingIndicatorCount(.two, in: configuration)
    configuration = NotchHUDConfigurationPolicy.settingSecondaryMetric(
      .temperature,
      in: configuration)
    configuration.colorMode = .custom
    configuration.accent = .mint
    configuration.lineThickness = 4
    configuration.horizontalExtension = 120
    configuration.showValueText = false
    configuration.secondaryWarningThreshold = 78
    configuration.secondaryCriticalThreshold = 92

    let data = try XCTUnwrap(NotchHUDConfigurationPersistence.encode(configuration))
    let restored = try XCTUnwrap(NotchHUDConfigurationPersistence.decode(data))

    XCTAssertEqual(restored, NotchHUDConfigurationPolicy.normalized(configuration))
    XCTAssertEqual(restored.indicatorCount, .two)
    XCTAssertEqual(restored.secondaryMetric, .temperature)
    XCTAssertFalse(restored.showValueText)
  }

  func testBatteryThresholdOrderIsNormalizedForLowerIsWorse() {
    var configuration = NotchHUDConfiguration.configuration(for: .battery)
    configuration.warningThreshold = 10
    configuration.criticalThreshold = 25

    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    XCTAssertEqual(normalized.warningThreshold, 25)
    XCTAssertEqual(normalized.criticalThreshold, 10)
  }

  func testSecondaryBatteryThresholdOrderIsNormalizedIndependently() {
    var configuration = NotchHUDConfiguration.configuration(for: .cpu)
    configuration.secondaryMetric = .battery
    configuration.secondaryWarningThreshold = 10
    configuration.secondaryCriticalThreshold = 25

    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    XCTAssertEqual(normalized.secondaryWarningThreshold, 25)
    XCTAssertEqual(normalized.secondaryCriticalThreshold, 10)
  }
}
