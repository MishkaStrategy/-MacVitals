import Foundation

nonisolated enum StatusBarPetSize: String, Codable, CaseIterable, Identifiable, Sendable {
  case tiny
  case small
  case medium

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .tiny: return StatusBarPetL10n.string("Tiny")
    case .small: return StatusBarPetL10n.string("Small")
    case .medium: return StatusBarPetL10n.string("Medium")
    }
  }

  var width: Double {
    switch self {
    case .tiny: return 76
    case .small: return 96
    case .medium: return 116
    }
  }

  var height: Double {
    switch self {
    case .tiny: return 58
    case .small: return 72
    case .medium: return 86
    }
  }
}

nonisolated struct StatusBarPetConfiguration: Codable, Equatable, Sendable {
  var isEnabled: Bool
  var roamEnabled: Bool
  var cursorInteractionEnabled: Bool
  var respectReducedMotion: Bool
  var size: StatusBarPetSize
  var movementSpeed: Double
  var sparkIntensity: Double

  static let electricDragon = StatusBarPetConfiguration(
    isEnabled: false,
    roamEnabled: true,
    cursorInteractionEnabled: true,
    respectReducedMotion: true,
    size: .small,
    movementSpeed: 1,
    sparkIntensity: 0.55)
}

nonisolated enum StatusBarPetConfigurationPolicy {
  static func normalized(_ configuration: StatusBarPetConfiguration)
    -> StatusBarPetConfiguration
  {
    var result = configuration
    result.movementSpeed = min(max(result.movementSpeed, 0.45), 1.8)
    result.sparkIntensity = min(max(result.sparkIntensity, 0), 1)
    return result
  }
}

nonisolated enum StatusBarPetConfigurationPersistence {
  static let currentSchemaVersion = 1

  private struct StoredConfiguration: Codable {
    let schemaVersion: Int
    let configuration: StatusBarPetConfiguration
  }

  static func encode(_ configuration: StatusBarPetConfiguration) -> Data? {
    let stored = StoredConfiguration(
      schemaVersion: currentSchemaVersion,
      configuration: StatusBarPetConfigurationPolicy.normalized(configuration))
    return try? JSONEncoder().encode(stored)
  }

  static func decode(_ data: Data) -> StatusBarPetConfiguration? {
    guard let stored = try? JSONDecoder().decode(StoredConfiguration.self, from: data),
      stored.schemaVersion == currentSchemaVersion
    else {
      return nil
    }
    return StatusBarPetConfigurationPolicy.normalized(stored.configuration)
  }
}

nonisolated enum StatusBarPetMotionRules {
  static let hardwareNotchWidth = 212.0
  static let minimumSafeAreaTop = 30.0
  static let maximumSafeAreaTop = 44.0
  static let sidePlayground = 32.0
  static let cursorInteractionRadius = 104.0
  static let cursorHorizontalPadding = 42.0
  static let cursorBottomPadding = 68.0
  static let maximumBodyRotationDegrees = 16.0
  static let modelEdgeMargin = 6.0

  static func resolvedSafeAreaTop(_ safeAreaTop: Double) -> Double {
    guard safeAreaTop > 0 else { return minimumSafeAreaTop }
    return min(max(safeAreaTop, minimumSafeAreaTop), maximumSafeAreaTop)
  }

  static func panelWidth(for size: StatusBarPetSize) -> Double {
    hardwareNotchWidth + sidePlayground * 2 + size.width * 0.30
  }

  static func panelHeight(safeAreaTop: Double, size: StatusBarPetSize) -> Double {
    resolvedSafeAreaTop(safeAreaTop) + size.height + 18
  }

  static func notchEdges(panelWidth: Double) -> (left: Double, right: Double) {
    let left = (panelWidth - hardwareNotchWidth) / 2
    return (left, left + hardwareNotchWidth)
  }

  static func rotatedHorizontalHalfExtent(
    petWidth: Double,
    petHeight: Double,
    degrees: Double = maximumBodyRotationDegrees
  ) -> Double {
    let radians = abs(degrees) * .pi / 180
    return abs(cos(radians)) * petWidth / 2
      + abs(sin(radians)) * petHeight / 2
  }

  static func roamBounds(
    panelWidth: Double,
    petWidth: Double,
    petHeight: Double
  ) -> ClosedRange<Double> {
    let edges = notchEdges(panelWidth: panelWidth)
    let overshoot = min(sidePlayground * 0.42, petWidth * 0.20)
    let halfExtent = rotatedHorizontalHalfExtent(
      petWidth: petWidth,
      petHeight: petHeight)
    let minimumCenter = halfExtent + modelEdgeMargin
    let maximumCenter = panelWidth - halfExtent - modelEdgeMargin
    let lower = max(minimumCenter, edges.left - overshoot)
    let upper = min(maximumCenter, edges.right + overshoot)
    return lower...max(lower, upper)
  }

  static func roamBounds(panelWidth: Double, petWidth: Double) -> ClosedRange<Double> {
    roamBounds(
      panelWidth: panelWidth,
      petWidth: petWidth,
      petHeight: petWidth * 0.75)
  }

  static func clamped(_ x: Double, to bounds: ClosedRange<Double>) -> Double {
    min(max(x, bounds.lowerBound), bounds.upperBound)
  }

  static func petY(
    x: Double,
    panelWidth: Double,
    safeAreaTop: Double,
    petWidth: Double,
    petHeight: Double
  ) -> Double {
    let edges = notchEdges(panelWidth: panelWidth)
    let bounds = roamBounds(
      panelWidth: panelWidth,
      petWidth: petWidth,
      petHeight: petHeight)
    let resolvedTop = resolvedSafeAreaTop(safeAreaTop)
    let shoulderY = max(petHeight * 0.52, resolvedTop * 0.34)
    let bottomY = resolvedTop + petHeight * 0.18 + 2
    let inset = min(petWidth * 0.12, 9)
    let leftBottomX = max(bounds.lowerBound, edges.left + inset)
    let rightBottomX = min(bounds.upperBound, edges.right - inset)

    if x <= leftBottomX {
      let progress = min(
        max((x - bounds.lowerBound) / max(1, leftBottomX - bounds.lowerBound), 0),
        1)
      return shoulderY + (bottomY - shoulderY) * progress
    }

    if x >= rightBottomX {
      let progress = min(
        max((bounds.upperBound - x) / max(1, bounds.upperBound - rightBottomX), 0),
        1)
      return shoulderY + (bottomY - shoulderY) * progress
    }

    return bottomY
  }

  static func petY(
    x: Double,
    panelWidth: Double,
    safeAreaTop: Double,
    petHeight: Double
  ) -> Double {
    petY(
      x: x,
      panelWidth: panelWidth,
      safeAreaTop: safeAreaTop,
      petWidth: petHeight / 0.75,
      petHeight: petHeight)
  }

  static func shouldPlay(
    petX: Double,
    cursorX: Double,
    cursorY: Double,
    panelWidth: Double,
    safeAreaTop: Double,
    interactionEnabled: Bool
  ) -> Bool {
    guard interactionEnabled else { return false }
    let edges = notchEdges(panelWidth: panelWidth)
    let maximumY = resolvedSafeAreaTop(safeAreaTop) + cursorBottomPadding
    let insideNotchZone = cursorX >= edges.left - cursorHorizontalPadding
      && cursorX <= edges.right + cursorHorizontalPadding
      && cursorY >= 0
      && cursorY <= maximumY
    return insideNotchZone && abs(cursorX - petX) <= cursorInteractionRadius
  }

  static func advancedX(
    current: Double,
    target: Double,
    pointsPerSecond: Double,
    deltaTime: Double
  ) -> Double {
    guard deltaTime > 0, pointsPerSecond > 0 else { return current }
    let difference = target - current
    let step = min(abs(difference), pointsPerSecond * deltaTime)
    return current + (difference < 0 ? -step : step)
  }
}
