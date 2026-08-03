import XCTest
@testable import MacVitals

final class StatusBarPetContourMotionTests: XCTestCase {
  func testContourRunsFromLeftPerchAcrossBottomToRightPerch() {
    let panelWidth = StatusBarPetMotionRules.panelWidth(for: .small)
    let left = StatusBarPetContourPath.sample(
      progress: 0,
      panelWidth: panelWidth,
      safeAreaTop: 38,
      petWidth: StatusBarPetSize.small.width,
      petHeight: StatusBarPetSize.small.height)
    let center = StatusBarPetContourPath.sample(
      progress: 0.5,
      panelWidth: panelWidth,
      safeAreaTop: 38,
      petWidth: StatusBarPetSize.small.width,
      petHeight: StatusBarPetSize.small.height)
    let right = StatusBarPetContourPath.sample(
      progress: 1,
      panelWidth: panelWidth,
      safeAreaTop: 38,
      petWidth: StatusBarPetSize.small.width,
      petHeight: StatusBarPetSize.small.height)

    XCTAssertLessThan(left.x, center.x)
    XCTAssertLessThan(center.x, right.x)
    XCTAssertLessThan(left.y, center.y)
    XCTAssertLessThan(right.y, center.y)
  }

  func testContourKeepsFullDragonInsideOverlay() {
    for size in StatusBarPetSize.allCases {
      let panelWidth = StatusBarPetMotionRules.panelWidth(for: size)
      for index in 0...40 {
        let sample = StatusBarPetContourPath.sample(
          progress: Double(index) / 40,
          panelWidth: panelWidth,
          safeAreaTop: 38,
          petWidth: size.width,
          petHeight: size.height)

        XCTAssertGreaterThanOrEqual(sample.x - size.width / 2, 5)
        XCTAssertLessThanOrEqual(sample.x + size.width / 2, panelWidth - 5)
        XCTAssertGreaterThanOrEqual(sample.y, 0)
      }
    }
  }

  func testShouldersTiltInOppositeDirections() {
    let panelWidth = StatusBarPetMotionRules.panelWidth(for: .small)
    let left = StatusBarPetContourPath.sample(
      progress: 0.12,
      panelWidth: panelWidth,
      safeAreaTop: 38,
      petWidth: StatusBarPetSize.small.width,
      petHeight: StatusBarPetSize.small.height)
    let right = StatusBarPetContourPath.sample(
      progress: 0.88,
      panelWidth: panelWidth,
      safeAreaTop: 38,
      petWidth: StatusBarPetSize.small.width,
      petHeight: StatusBarPetSize.small.height)

    XCTAssertGreaterThan(left.tangentDegrees, 0)
    XCTAssertLessThan(right.tangentDegrees, 0)
    XCTAssertLessThanOrEqual(
      abs(left.tangentDegrees),
      StatusBarPetMotionRules.maximumBodyRotationDegrees)
    XCTAssertLessThanOrEqual(
      abs(right.tangentDegrees),
      StatusBarPetMotionRules.maximumBodyRotationDegrees)
  }

  func testCursorXMapsBackOntoContour() {
    let size = StatusBarPetSize.small
    let panelWidth = StatusBarPetMotionRules.panelWidth(for: size)
    let expected = StatusBarPetContourPath.sample(
      progress: 0.72,
      panelWidth: panelWidth,
      safeAreaTop: 38,
      petWidth: size.width,
      petHeight: size.height)
    let resolved = StatusBarPetContourPath.progress(
      nearestToX: expected.x,
      panelWidth: panelWidth,
      safeAreaTop: 38,
      petWidth: size.width,
      petHeight: size.height)

    XCTAssertEqual(resolved, 0.72, accuracy: 0.02)
  }

  func testProgressAdvanceNeverOvershoots() {
    let size = StatusBarPetSize.small
    let panelWidth = StatusBarPetMotionRules.panelWidth(for: size)
    let result = StatusBarPetContourPath.advancedProgress(
      current: 0.45,
      target: 0.46,
      pointsPerSecond: 500,
      deltaTime: 1,
      panelWidth: panelWidth,
      safeAreaTop: 38,
      petWidth: size.width,
      petHeight: size.height)

    XCTAssertEqual(result, 0.46, accuracy: 0.0001)
  }

  func testKinematicsSlowDownNearPerch() {
    let farSpeed = StatusBarPetKinematics.targetSpeed(
      maximumSpeed: 40,
      remainingDistance: 80,
      slowdownDistance: 30)
    let nearSpeed = StatusBarPetKinematics.targetSpeed(
      maximumSpeed: 40,
      remainingDistance: 8,
      slowdownDistance: 30)
    let stoppedSpeed = StatusBarPetKinematics.targetSpeed(
      maximumSpeed: 40,
      remainingDistance: 0,
      slowdownDistance: 30)

    XCTAssertEqual(farSpeed, 40, accuracy: 0.001)
    XCTAssertGreaterThan(nearSpeed, 0)
    XCTAssertLessThan(nearSpeed, farSpeed)
    XCTAssertEqual(stoppedSpeed, 0, accuracy: 0.001)
  }

  func testKinematicsAccelerationNeverOvershootsDesiredSpeed() {
    XCTAssertEqual(
      StatusBarPetKinematics.advancedSpeed(
        current: 0,
        target: 40,
        acceleration: 100,
        deltaTime: 0.1),
      10,
      accuracy: 0.001)
    XCTAssertEqual(
      StatusBarPetKinematics.advancedSpeed(
        current: 38,
        target: 40,
        acceleration: 100,
        deltaTime: 0.1),
      40,
      accuracy: 0.001)
    XCTAssertEqual(
      StatusBarPetKinematics.advancedSpeed(
        current: 5,
        target: 0,
        acceleration: 100,
        deltaTime: 0.1),
      0,
      accuracy: 0.001)
  }
}
