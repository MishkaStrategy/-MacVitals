import Foundation

nonisolated enum NotchIndicatorCount: String, Codable, CaseIterable, Identifiable, Sendable {
  case one
  case two

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .one: return L10n.string("One indicator")
    case .two: return L10n.string("Two indicators")
    }
  }
}

nonisolated enum NotchIndicatorColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case automatic
  case accent
  case custom

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .automatic: return L10n.string("Automatic")
    case .accent: return L10n.string("System accent")
    case .custom: return L10n.string("Custom color")
    }
  }
}

nonisolated enum NotchIndicatorAccent: String, Codable, CaseIterable, Identifiable, Sendable {
  case blue, cyan, mint, green, yellow, orange, red, pink, purple, white

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .blue: return L10n.string("Blue")
    case .cyan: return L10n.string("Cyan")
    case .mint: return L10n.string("Mint")
    case .green: return L10n.string("Green")
    case .yellow: return L10n.string("Yellow")
    case .orange: return L10n.string("Orange")
    case .red: return L10n.string("Red")
    case .pink: return L10n.string("Pink")
    case .purple: return L10n.string("Purple")
    case .white: return L10n.string("White")
    }
  }
}

nonisolated struct NotchIndicatorThresholds: Codable, Equatable, Sendable {
  var warning: Double
  var critical: Double
}

extension MenuMetric {
  nonisolated static var notchIndicatorMetrics: [MenuMetric] {
    allCases.filter { $0 != .powerStatus }
  }

  nonisolated var notchIndicatorRange: ClosedRange<Double> {
    switch self {
    case .cpu, .gpu, .memory, .temperature, .battery:
      return 0...100
    case .fans:
      return 0...6_000
    case .systemPower:
      return 0...120
    case .adapterPower:
      return 0...160
    case .powerStatus:
      return 0...1
    }
  }

  nonisolated var notchIndicatorDefaultThresholds: NotchIndicatorThresholds {
    switch self {
    case .cpu, .gpu:
      return NotchIndicatorThresholds(warning: 75, critical: 90)
    case .memory:
      return NotchIndicatorThresholds(warning: 80, critical: 92)
    case .temperature:
      return NotchIndicatorThresholds(warning: 75, critical: 90)
    case .battery:
      return NotchIndicatorThresholds(warning: 25, critical: 10)
    case .fans:
      return NotchIndicatorThresholds(warning: 4_500, critical: 5_500)
    case .systemPower:
      return NotchIndicatorThresholds(warning: 60, critical: 90)
    case .adapterPower:
      return NotchIndicatorThresholds(warning: 100, critical: 140)
    case .powerStatus:
      return NotchIndicatorThresholds(warning: 1, critical: 1)
    }
  }

  nonisolated var notchIndicatorLowerIsWorse: Bool {
    self == .battery
  }
}

nonisolated struct NotchHUDConfiguration: Codable, Equatable, Sendable {
  var metric: MenuMetric
  var secondaryMetric: MenuMetric?
  var showValueText: Bool
  var showSensorName: Bool
  var colorMode: NotchIndicatorColorMode
  var accent: NotchIndicatorAccent
  var lineThickness: Double
  var horizontalExtension: Double
  var trackOpacity: Double
  var glowIntensity: Double
  var warningThreshold: Double
  var criticalThreshold: Double
  var secondaryWarningThreshold: Double?
  var secondaryCriticalThreshold: Double?
  var animateChanges: Bool
  var showOnDisplaysWithoutNotch: Bool

  var indicatorCount: NotchIndicatorCount {
    secondaryMetric == nil ? .one : .two
  }

  static let minimal = configuration(for: .cpu)
  static let balanced = minimal
  static let detailed = minimal

  static func configuration(for metric: MenuMetric) -> NotchHUDConfiguration {
    let resolvedMetric = MenuMetric.notchIndicatorMetrics.contains(metric) ? metric : .cpu
    let thresholds = resolvedMetric.notchIndicatorDefaultThresholds
    return NotchHUDConfiguration(
      metric: resolvedMetric,
      secondaryMetric: nil,
      showValueText: true,
      showSensorName: true,
      colorMode: .automatic,
      accent: .cyan,
      lineThickness: 2.5,
      horizontalExtension: 72,
      trackOpacity: 0.18,
      glowIntensity: 0.62,
      warningThreshold: thresholds.warning,
      criticalThreshold: thresholds.critical,
      secondaryWarningThreshold: nil,
      secondaryCriticalThreshold: nil,
      animateChanges: true,
      showOnDisplaysWithoutNotch: false)
  }
}

// Compatibility shims keep existing SettingsStore call sites source-compatible while the
// former two-panel HUD is replaced by one contour indicator.
nonisolated enum NotchHUDSide: String, Codable, CaseIterable, Identifiable, Sendable {
  case left
  case right

  var id: String { rawValue }
}

nonisolated enum NotchHUDPreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case minimal
  case balanced
  case detailed
  case custom

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .minimal: return L10n.string("Default")
    case .balanced: return L10n.string("Default")
    case .detailed: return L10n.string("Default")
    case .custom: return L10n.string("Custom")
    }
  }

  var configuration: NotchHUDConfiguration { .minimal }
}

nonisolated enum NotchHUDConfigurationPolicy {
  static func normalized(_ configuration: NotchHUDConfiguration) -> NotchHUDConfiguration {
    var result = configuration
    if !MenuMetric.notchIndicatorMetrics.contains(result.metric) {
      result.metric = .cpu
    }

    result.lineThickness = min(max(result.lineThickness, 1), 6)
    result.horizontalExtension = min(max(result.horizontalExtension, 36), 180)
    result.trackOpacity = min(max(result.trackOpacity, 0.05), 0.55)
    result.glowIntensity = min(max(result.glowIntensity, 0), 1)

    let primaryThresholds = normalizedThresholds(
      metric: result.metric,
      warning: result.warningThreshold,
      critical: result.criticalThreshold)
    result.warningThreshold = primaryThresholds.warning
    result.criticalThreshold = primaryThresholds.critical

    if let requestedSecondary = result.secondaryMetric {
      let secondary = resolvedSecondaryMetric(requestedSecondary, excluding: result.metric)
      let defaults = secondary.notchIndicatorDefaultThresholds
      let secondaryThresholds = normalizedThresholds(
        metric: secondary,
        warning: result.secondaryWarningThreshold ?? defaults.warning,
        critical: result.secondaryCriticalThreshold ?? defaults.critical)
      result.secondaryMetric = secondary
      result.secondaryWarningThreshold = secondaryThresholds.warning
      result.secondaryCriticalThreshold = secondaryThresholds.critical
    } else {
      result.secondaryWarningThreshold = nil
      result.secondaryCriticalThreshold = nil
    }

    return result
  }

  static func settingIndicatorCount(
    _ count: NotchIndicatorCount,
    in configuration: NotchHUDConfiguration
  ) -> NotchHUDConfiguration {
    var result = configuration
    switch count {
    case .one:
      result.secondaryMetric = nil
      result.secondaryWarningThreshold = nil
      result.secondaryCriticalThreshold = nil
    case .two:
      if result.secondaryMetric == nil {
        let metric = defaultSecondaryMetric(excluding: result.metric)
        let thresholds = metric.notchIndicatorDefaultThresholds
        result.secondaryMetric = metric
        result.secondaryWarningThreshold = thresholds.warning
        result.secondaryCriticalThreshold = thresholds.critical
      }
    }
    return normalized(result)
  }

  static func setting(
    _ metric: MenuMetric,
    side: NotchHUDSide?,
    in configuration: NotchHUDConfiguration
  ) -> NotchHUDConfiguration {
    switch side {
    case .right:
      return settingSecondaryMetric(metric, in: configuration)
    case .left, nil:
      var result = configuration
      let resolvedMetric = resolvedMetric(metric)
      result.metric = resolvedMetric
      let thresholds = resolvedMetric.notchIndicatorDefaultThresholds
      result.warningThreshold = thresholds.warning
      result.criticalThreshold = thresholds.critical
      return normalized(result)
    }
  }

  static func settingSecondaryMetric(
    _ metric: MenuMetric,
    in configuration: NotchHUDConfiguration
  ) -> NotchHUDConfiguration {
    var result = configuration
    let resolvedMetric = resolvedSecondaryMetric(metric, excluding: result.metric)
    let thresholds = resolvedMetric.notchIndicatorDefaultThresholds
    result.secondaryMetric = resolvedMetric
    result.secondaryWarningThreshold = thresholds.warning
    result.secondaryCriticalThreshold = thresholds.critical
    return normalized(result)
  }

  static func moving(
    _: MenuMetric,
    towardStart _: Bool,
    in configuration: NotchHUDConfiguration
  ) -> NotchHUDConfiguration {
    normalized(configuration)
  }

  static func resolvedPreset(for configuration: NotchHUDConfiguration) -> NotchHUDPreset {
    normalized(configuration) == .minimal ? .minimal : .custom
  }

  private static func resolvedMetric(_ metric: MenuMetric) -> MenuMetric {
    MenuMetric.notchIndicatorMetrics.contains(metric) ? metric : .cpu
  }

  private static func resolvedSecondaryMetric(
    _ metric: MenuMetric,
    excluding primaryMetric: MenuMetric
  ) -> MenuMetric {
    let resolved = resolvedMetric(metric)
    return resolved == primaryMetric ? defaultSecondaryMetric(excluding: primaryMetric) : resolved
  }

  private static func defaultSecondaryMetric(excluding primaryMetric: MenuMetric) -> MenuMetric {
    let preferred: [MenuMetric] = [.temperature, .memory, .battery, .gpu, .fans]
    return preferred.first(where: { $0 != primaryMetric })
      ?? MenuMetric.notchIndicatorMetrics.first(where: { $0 != primaryMetric })
      ?? .cpu
  }

  private static func normalizedThresholds(
    metric: MenuMetric,
    warning: Double,
    critical: Double
  ) -> NotchIndicatorThresholds {
    let range = metric.notchIndicatorRange
    var normalizedWarning = min(max(warning, range.lowerBound), range.upperBound)
    var normalizedCritical = min(max(critical, range.lowerBound), range.upperBound)

    if metric.notchIndicatorLowerIsWorse {
      if normalizedWarning < normalizedCritical {
        swap(&normalizedWarning, &normalizedCritical)
      }
    } else if normalizedWarning > normalizedCritical {
      swap(&normalizedWarning, &normalizedCritical)
    }

    return NotchIndicatorThresholds(
      warning: normalizedWarning,
      critical: normalizedCritical)
  }
}

nonisolated enum NotchHUDConfigurationPersistence {
  static let currentSchemaVersion = 4

  private struct VersionEnvelope: Decodable {
    let schemaVersion: Int
  }

  private struct StoredConfiguration: Codable {
    let schemaVersion: Int
    let configuration: NotchHUDConfiguration
  }

  private struct LegacyStoredConfiguration: Decodable {
    let schemaVersion: Int
    let configuration: LegacyConfiguration
  }

  private struct LegacyConfiguration: Decodable {
    let leftMetrics: [MenuMetric]?
    let rightMetrics: [MenuMetric]?

    var migrated: NotchHUDConfiguration {
      let candidate = (leftMetrics ?? []) + (rightMetrics ?? [])
      let metric = candidate.first(where: { MenuMetric.notchIndicatorMetrics.contains($0) }) ?? .cpu
      return .configuration(for: metric)
    }
  }

  static func encode(_ configuration: NotchHUDConfiguration) -> Data? {
    try? JSONEncoder().encode(
      StoredConfiguration(
        schemaVersion: currentSchemaVersion,
        configuration: NotchHUDConfigurationPolicy.normalized(configuration)))
  }

  static func decode(_ data: Data) -> NotchHUDConfiguration? {
    guard let envelope = try? JSONDecoder().decode(VersionEnvelope.self, from: data) else {
      return nil
    }

    switch envelope.schemaVersion {
    case currentSchemaVersion, 3:
      guard let stored = try? JSONDecoder().decode(StoredConfiguration.self, from: data) else {
        return nil
      }
      return NotchHUDConfigurationPolicy.normalized(stored.configuration)
    case 1, 2:
      guard let stored = try? JSONDecoder().decode(LegacyStoredConfiguration.self, from: data)
      else {
        return nil
      }
      return NotchHUDConfigurationPolicy.normalized(stored.configuration.migrated)
    default:
      return nil
    }
  }
}
