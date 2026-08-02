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
    case .tiny: return 30
    case .small: return 38
    case .medium: return 46
    }
  }

  var height: Double {
    switch self {
    case .tiny: return 23
    case .small: return 29
    case .medium: return 35
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
    sparkIntensity: 0.75)
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
  static let cursorInteractionRadius = 92.0
  static let cursorInteractionTopDistance = 78.0

  static func roamBounds(screenWidth: Double, anchorX: Double?) -> ClosedRange<Double> {
    let center = anchorX ?? screenWidth * 0.72
    let lower = max(24, center - 280)
    let upper = min(screenWidth - 24, center + 280)
    if lower <= upper { return lower...upper }
    let fallback = min(max(center, 24), max(24, screenWidth - 24))
    return fallback...fallback
  }

  static func clamped(_ x: Double, to bounds: ClosedRange<Double>) -> Double {
    min(max(x, bounds.lowerBound), bounds.upperBound)
  }

  static func shouldPlay(
    petX: Double,
    cursorX: Double,
    cursorDistanceFromTop: Double,
    interactionEnabled: Bool
  ) -> Bool {
    interactionEnabled
      && cursorDistanceFromTop >= 0
      && cursorDistanceFromTop <= cursorInteractionTopDistance
      && abs(cursorX - petX) <= cursorInteractionRadius
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

  static func avoidingNotch(
    target: Double,
    screenWidth: Double,
    safeAreaTop: Double,
    anchorX: Double?
  ) -> Double {
    guard safeAreaTop > 0 else { return target }
    let center = screenWidth / 2
    let exclusionHalfWidth = 124.0
    guard target > center - exclusionHalfWidth, target < center + exclusionHalfWidth else {
      return target
    }
    return (anchorX ?? target) < center
      ? center - exclusionHalfWidth - 18
      : center + exclusionHalfWidth + 18
  }
}
