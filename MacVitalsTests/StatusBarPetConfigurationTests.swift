import XCTest
@testable import MacVitals

final class StatusBarPetConfigurationTests: XCTestCase {
  func testDefaultConfigurationIsDisabledAndInteractive() {
    let configuration = StatusBarPetConfiguration.electricDragon

    XCTAssertFalse(configuration.isEnabled)
    XCTAssertTrue(configuration.roamEnabled)
    XCTAssertTrue(configuration.cursorInteractionEnabled)
    XCTAssertTrue(configuration.respectReducedMotion)
    XCTAssertEqual(configuration.size, .small)
    XCTAssertEqual(configuration.movementSpeed, 1, accuracy: 0.001)
    XCTAssertEqual(configuration.sparkIntensity, 0.75, accuracy: 0.001)
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

  func testCursorInteractionRequiresNearbyTopBarCursor() {
    XCTAssertTrue(
      StatusBarPetMotionRules.shouldPlay(
        petX: 500,
        cursorX: 548,
        cursorDistanceFromTop: 30,
        interactionEnabled: true))
    XCTAssertFalse(
      StatusBarPetMotionRules.shouldPlay(
        petX: 500,
        cursorX: 640,
        cursorDistanceFromTop: 30,
        interactionEnabled: true))
    XCTAssertFalse(
      StatusBarPetMotionRules.shouldPlay(
        petX: 500,
        cursorX: 548,
        cursorDistanceFromTop: 120,
        interactionEnabled: true))
    XCTAssertFalse(
      StatusBarPetMotionRules.shouldPlay(
        petX: 500,
        cursorX: 548,
        cursorDistanceFromTop: 30,
        interactionEnabled: false))
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

  func testRoamBoundsStayNearStatusItem() {
    let bounds = StatusBarPetMotionRules.roamBounds(screenWidth: 1512, anchorX: 1100)

    XCTAssertEqual(bounds.lowerBound, 820, accuracy: 0.001)
    XCTAssertEqual(bounds.upperBound, 1380, accuracy: 0.001)
  }

  func testNotchAvoidanceMovesTargetToAnchorSide() {
    XCTAssertLessThan(
      StatusBarPetMotionRules.avoidingNotch(
        target: 756,
        screenWidth: 1512,
        safeAreaTop: 38,
        anchorX: 300),
      632)
    XCTAssertGreaterThan(
      StatusBarPetMotionRules.avoidingNotch(
        target: 756,
        screenWidth: 1512,
        safeAreaTop: 38,
        anchorX: 1200),
      880)
  }
}
