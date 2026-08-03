import CoreGraphics
import Foundation

nonisolated struct StatusBarPetContourSample: Equatable, Sendable {
  let progress: Double
  let x: Double
  let y: Double
  let tangentDegrees: Double
  let shoulderBlend: Double
}

nonisolated enum StatusBarPetContourPath {
  static let leftPerchProgress = 0.04
  static let leftShoulderProgress = 0.20
  static let centerProgress = 0.50
  static let rightShoulderProgress = 0.80
  static let rightPerchProgress = 0.96

  static func normalizedProgress(_ progress: Double) -> Double {
    min(max(progress, 0), 1)
  }

  static func sample(
    progress: Double,
    panelWidth: Double,
    safeAreaTop: Double,
    petWidth: Double,
    petHeight: Double
  ) -> StatusBarPetContourSample {
    let resolved = normalizedProgress(progress)
    let currentPosition = position(
      progress: resolved,
      panelWidth: panelWidth,
      safeAreaTop: safeAreaTop,
      petWidth: petWidth,
      petHeight: petHeight)
    let epsilon = 0.0025
    let previous = position(
      progress: normalizedProgress(resolved - epsilon),
      panelWidth: panelWidth,
      safeAreaTop: safeAreaTop,
      petWidth: petWidth,
      petHeight: petHeight)
    let next = position(
      progress: normalizedProgress(resolved + epsilon),
      panelWidth: panelWidth,
      safeAreaTop: safeAreaTop,
      petWidth: petWidth,
      petHeight: petHeight)
    let angle = atan2(next.y - previous.y, next.x - previous.x) * 180 / .pi
    let shoulderBlend = min(
      shoulderWeight(progress: resolved, center: leftShoulderProgress),
      shoulderWeight(progress: resolved, center: rightShoulderProgress))

    return StatusBarPetContourSample(
      progress: resolved,
      x: currentPosition.x,
      y: currentPosition.y,
      tangentDegrees: min(
        max(angle, -StatusBarPetMotionRules.maximumBodyRotationDegrees),
        StatusBarPetMotionRules.maximumBodyRotationDegrees),
      shoulderBlend: 1 - shoulderBlend)
  }

  static func progress(
    nearestToX x: Double,
    panelWidth: Double,
    safeAreaTop: Double,
    petWidth: Double,
    petHeight: Double
  ) -> Double {
    var bestProgress = centerProgress
    var bestDistance = Double.greatestFiniteMagnitude

    for index in 0...120 {
      let candidate = Double(index) / 120
      let candidatePoint = position(
        progress: candidate,
        panelWidth: panelWidth,
        safeAreaTop: safeAreaTop,
        petWidth: petWidth,
        petHeight: petHeight)
      let distance = abs(candidatePoint.x - x)
      if distance < bestDistance {
        bestDistance = distance
        bestProgress = candidate
      }
    }

    return bestProgress
  }

  static func advancedProgress(
    current: Double,
    target: Double,
    pointsPerSecond: Double,
    deltaTime: Double,
    panelWidth: Double,
    safeAreaTop: Double,
    petWidth: Double,
    petHeight: Double
  ) -> Double {
    guard deltaTime > 0, pointsPerSecond > 0 else { return normalizedProgress(current) }
    let distance = pathLength(
      panelWidth: panelWidth,
      safeAreaTop: safeAreaTop,
      petWidth: petWidth,
      petHeight: petHeight)
    let progressPerSecond = pointsPerSecond / max(distance, 1)
    let difference = target - current
    let step = min(abs(difference), progressPerSecond * deltaTime)
    return normalizedProgress(current + (difference < 0 ? -step : step))
  }

  static func pathLength(
    panelWidth: Double,
    safeAreaTop: Double,
    petWidth: Double,
    petHeight: Double
  ) -> Double {
    var total = 0.0
    var previous = position(
      progress: 0,
      panelWidth: panelWidth,
      safeAreaTop: safeAreaTop,
      petWidth: petWidth,
      petHeight: petHeight)

    for index in 1...80 {
      let current = position(
        progress: Double(index) / 80,
        panelWidth: panelWidth,
        safeAreaTop: safeAreaTop,
        petWidth: petWidth,
        petHeight: petHeight)
      total += hypot(current.x - previous.x, current.y - previous.y)
      previous = current
    }

    return total
  }

  private static func position(
    progress: Double,
    panelWidth: Double,
    safeAreaTop: Double,
    petWidth: Double,
    petHeight: Double
  ) -> (x: Double, y: Double) {
    let resolved = normalizedProgress(progress)
    let bounds = StatusBarPetMotionRules.roamBounds(
      panelWidth: panelWidth,
      petWidth: petWidth,
      petHeight: petHeight)
    let edges = StatusBarPetMotionRules.notchEdges(panelWidth: panelWidth)
    let resolvedTop = StatusBarPetMotionRules.resolvedSafeAreaTop(safeAreaTop)
    let outerY = max(petHeight * 0.46, resolvedTop * 0.31)
    let bottomY = resolvedTop + petHeight * 0.16 + 2
    let inset = min(petWidth * 0.12, 9)
    let leftBottomX = max(bounds.lowerBound, edges.left + inset)
    let rightBottomX = min(bounds.upperBound, edges.right - inset)

    if resolved <= leftShoulderProgress {
      let local = smoothStep(resolved / leftShoulderProgress)
      return (
        interpolate(bounds.lowerBound, leftBottomX, local),
        interpolate(outerY, bottomY, local))
    }

    if resolved >= rightShoulderProgress {
      let local = smoothStep((resolved - rightShoulderProgress) / (1 - rightShoulderProgress))
      return (
        interpolate(rightBottomX, bounds.upperBound, local),
        interpolate(bottomY, outerY, local))
    }

    let local = (resolved - leftShoulderProgress)
      / (rightShoulderProgress - leftShoulderProgress)
    let sag = sin(local * .pi) * min(2.2, petHeight * 0.035)
    return (
      interpolate(leftBottomX, rightBottomX, local),
      bottomY + sag)
  }

  private static func smoothStep(_ value: Double) -> Double {
    let resolved = min(max(value, 0), 1)
    return resolved * resolved * (3 - 2 * resolved)
  }

  private static func interpolate(_ from: Double, _ to: Double, _ progress: Double) -> Double {
    from + (to - from) * progress
  }

  private static func shoulderWeight(progress: Double, center: Double) -> Double {
    min(abs(progress - center) / 0.20, 1)
  }
}
