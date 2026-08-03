import XCTest
@testable import MacVitals

final class StatusBarPetConfigurationTests: XCTestCase {
  func testDefaultConfigurationIsDisabledAndNotchInteractive() {
    let configuration = StatusBarPetConfiguration.electricDragon

    XCTAssertFalse(configuration.isEnabled)
    XCTAssertTrue(configuration.roamEnabled)
    XCTAssertTrue(configuration.cursorInteractionEnabled)
    XCTAssertTrue(configuration.respectReducedMotion)
    XCTAssertEqual(configuration.size, .small)
    XCTAssertEqual(configuration.movementSpeed, 1, accuracy: 0.001)
    XCTAssertEqual(configuration.sparkIntensity, 0.55, accuracy: 0.001)
  }

  func testPolicyClampsNumericValues() {
    var configuration = StatusBarPetConfiguration.electricDragon
    configuration.movementSpeed = 4
    configuration.sparkIntensity = -2

    let normalized = StatusBarPetConfigurationPolicy.normalized(configuration)

    XCTAssertEqual(normalized.movementSpeed, 1.8, accuracy: 0.001)
    XCTAssertEqual(normalized.sparkIntensity, 0, accuracy: 0.001)
  }

  func testPersistenceRoundTrip() throws {
    var configuration = StatusBarPetConfiguration.electricDragon
    configuration.isEnabled = true
    configuration.size = .tiny
    configuration.movementSpeed = 1.35
    configuration.sparkIntensity = 0.4

    let data = try XCTUnwrap(StatusBarPetConfigurationPersistence.encode(configuration))
    let decoded = try XCTUnwrap(StatusBarPetConfigurationPersistence.decode(data))

    XCTAssertEqual(decoded, configuration)
  }

  func testDetailedModelSizesRemainNotchScoped() {
    XCTAssertEqual(StatusBarPetSize.tiny.width, 54, accuracy: 0.001)
    XCTAssertEqual(StatusBarPetSize.small.width, 66, accuracy: 0.001)
    XCTAssertEqual(StatusBarPetSize.medium.width, 78, accuracy: 0.001)

    for size in StatusBarPetSize.allCases {
      XCTAssertGreaterThan(size.width, size.height)
      XCTAssertGreaterThanOrEqual(size.height, 46)
      XCTAssertLessThan(StatusBarPetMotionRules.panelWidth(for: size), 320)
    }
  }

  func testPanelWidthIsLimitedToNotchNeighborhood() {
    let width = StatusBarPetMotionRules.panelWidth(for: .small)

    XCTAssertGreaterThan(width, StatusBarPetMotionRules.hardwareNotchWidth)
    XCTAssertLessThan(width, 320)
  }

  func testRoamBoundsStayOnNotchContourAndContainTheWholeModel() {
    let size = StatusBarPetSize.small
    let panelWidth = StatusBarPetMotionRules.panelWidth(for: size)
    let bounds = StatusBarPetMotionRules.roamBounds(
      panelWidth: panelWidth,
      petWidth: size.width)
    let edges = StatusBarPetMotionRules.notchEdges(panelWidth: panelWidth)

    XCTAssertLessThan(bounds.lowerBound, edges.left)
    XCTAssertGreaterThan(bounds.upperBound, edges.right)
    XCTAssertGreaterThanOrEqual(bounds.lowerBound - size.width / 2, 0)
    XCTAssertLessThanOrEqual(bounds.upperBound + size.width / 2, panelWidth)
    XCTAssertLessThan(bounds.upperBound - bounds.lowerBound, 270)
  }

  func testCursorInteractionWorksOnlyBesideNotch() {
    let panelWidth = StatusBarPetMotionRules.panelWidth(for: .small)

    XCTAssertTrue(
      StatusBarPetMotionRules.shouldPlay(
        petX: panelWidth / 2,
        cursorX: panelWidth / 2 + 35,
        cursorY: 42,
        panelWidth: panelWidth,
        safeAreaTop: 38,
        interactionEnabled: true))
    XCTAssertFalse(
      StatusBarPetMotionRules.shouldPlay(
        petX: panelWidth / 2,
        cursorX: panelWidth - 1,
        cursorY: 42,
        panelWidth: panelWidth,
        safeAreaTop: 38,
        interactionEnabled: true))
    XCTAssertFalse(
      StatusBarPetMotionRules.shouldPlay(
        petX: panelWidth / 2,
        cursorX: panelWidth / 2 + 20,
        cursorY: 100,
        panelWidth: panelWidth,
        safeAreaTop: 38,
        interactionEnabled: true))
    XCTAssertFalse(
      StatusBarPetMotionRules.shouldPlay(
        petX: panelWidth / 2,
        cursorX: panelWidth / 2 + 20,
        cursorY: 42,
        panelWidth: panelWidth,
        safeAreaTop: 38,
        interactionEnabled: false))
  }

  func testPetPathDropsAlongBottomEdgeAndClimbsShoulders() {
    let size = StatusBarPetSize.small
    let panelWidth = StatusBarPetMotionRules.panelWidth(for: size)
    let bounds = StatusBarPetMotionRules.roamBounds(
      panelWidth: panelWidth,
      petWidth: size.width)
    let centerY = StatusBarPetMotionRules.petY(
      x: panelWidth / 2,
      panelWidth: panelWidth,
      safeAreaTop: 38,
      petHeight: size.height)
    let shoulderY = StatusBarPetMotionRules.petY(
      x: bounds.lowerBound,
      panelWidth: panelWidth,
      safeAreaTop: 38,
      petHeight: size.height)

    XCTAssertGreaterThan(centerY, 38)
    XCTAssertLessThan(shoulderY, centerY)
    XCTAssertGreaterThanOrEqual(shoulderY, size.height * 0.5)
  }

  func testMovementNeverOvershootsTarget() {
    XCTAssertEqual(
      StatusBarPetMotionRules.advancedX(
        current: 100,
        target: 110,
        pointsPerSecond: 100,
        deltaTime: 0.2),
      110,
      accuracy: 0.001)
    XCTAssertEqual(
      StatusBarPetMotionRules.advancedX(
        current: 100,
        target: 200,
        pointsPerSecond: 50,
        deltaTime: 0.5),
      125,
      accuracy: 0.001)
  }
}
