import Foundation

nonisolated enum NotchHUDSide: String, Codable, CaseIterable, Identifiable, Sendable {
  case left
  case right

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .left: return L10n.string("Left panel")
    case .right: return L10n.string("Right panel")
    }
  }
}

nonisolated enum NotchHUDDensity: String, Codable, CaseIterable, Identifiable, Sendable {
  case compact
  case balanced
  case spacious

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .compact: return L10n.string("Compact")
    case .balanced: return L10n.string("Balanced")
    case .spacious: return L10n.string("Spacious")
    }
  }

  var panelHeight: Double {
    switch self {
    case .compact: return 24
    case .balanced: return 28
    case .spacious: return 32
    }
  }

  var horizontalPadding: Double {
    switch self {
    case .compact: return 7
    case .balanced: return 10
    case .spacious: return 12
    }
  }

  var itemSpacing: Double {
    switch self {
    case .compact: return 5
    case .balanced: return 8
    case .spacious: return 10
    }
  }

  var metricWidth: Double {
    switch self {
    case .compact: return 54
    case .balanced: return 62
    case .spacious: return 70
    }
  }

  var labeledMetricWidth: Double {
    switch self {
    case .compact: return 68
    case .balanced: return 76
    case .spacious: return 84
    }
  }
}

nonisolated enum NotchHUDTextSize: String, Codable, CaseIterable, Identifiable, Sendable {
  case small
  case medium
  case large

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .small: return L10n.string("Small")
    case .medium: return L10n.string("Medium")
    case .large: return L10n.string("Large")
    }
  }

  var scale: Double {
    switch self {
    case .small: return 0.88
    case .medium: return 1
    case .large: return 1.12
    }
  }
}

nonisolated struct NotchHUDConfiguration: Codable, Equatable, Sendable {
  var leftMetrics: [MenuMetric]
  var rightMetrics: [MenuMetric]
  var leftVisibleCount: Int
  var rightVisibleCount: Int
  var showLeftPanel: Bool
  var showRightPanel: Bool
  var density: NotchHUDDensity
  var textSize: NotchHUDTextSize
  var backgroundOpacity: Double
  var showLabels: Bool
  var showSeparators: Bool
  var hideUnavailableMetrics: Bool
  var showOnDisplaysWithoutNotch: Bool

  static let balanced = NotchHUDConfiguration(
    leftMetrics: [.cpu, .gpu, .memory],
    rightMetrics: [.fans, .temperature, .battery, .systemPower],
    leftVisibleCount: 3,
    rightVisibleCount: 4,
    showLeftPanel: true,
    showRightPanel: true,
    density: .balanced,
    textSize: .medium,
    backgroundOpacity: 0.62,
    showLabels: true,
    showSeparators: true,
    hideUnavailableMetrics: false,
    showOnDisplaysWithoutNotch: true)

  static let minimal = NotchHUDConfiguration(
    leftMetrics: [.cpu, .memory],
    rightMetrics: [.temperature, .battery],
    leftVisibleCount: 2,
    rightVisibleCount: 2,
    showLeftPanel: true,
    showRightPanel: true,
    density: .compact,
    textSize: .small,
    backgroundOpacity: 0.52,
    showLabels: false,
    showSeparators: false,
    hideUnavailableMetrics: true,
    showOnDisplaysWithoutNotch: false)

  static let detailed = NotchHUDConfiguration(
    leftMetrics: [.cpu, .gpu, .memory, .temperature],
    rightMetrics: [.fans, .battery, .systemPower, .adapterPower, .powerStatus],
    leftVisibleCount: 4,
    rightVisibleCount: 5,
    showLeftPanel: true,
    showRightPanel: true,
    density: .spacious,
    textSize: .medium,
    backgroundOpacity: 0.72,
    showLabels: true,
    showSeparators: true,
    hideUnavailableMetrics: false,
    showOnDisplaysWithoutNotch: true)

  func metrics(for side: NotchHUDSide) -> [MenuMetric] {
    switch side {
    case .left:
      guard showLeftPanel else { return [] }
      return Array(leftMetrics.prefix(leftVisibleCount))
    case .right:
      guard showRightPanel else { return [] }
      return Array(rightMetrics.prefix(rightVisibleCount))
    }
  }

  func placement(of metric: MenuMetric) -> NotchHUDSide? {
    if leftMetrics.contains(metric) { return .left }
    if rightMetrics.contains(metric) { return .right }
    return nil
  }
}

nonisolated enum NotchHUDPreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case minimal
  case balanced
  case detailed
  case custom

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .minimal: return L10n.string("Minimal")
    case .balanced: return L10n.string("Balanced")
    case .detailed: return L10n.string("Detailed")
    case .custom: return L10n.string("Custom")
    }
  }

  var configuration: NotchHUDConfiguration {
    switch self {
    case .minimal: return .minimal
    case .balanced: return .balanced
    case .detailed: return .detailed
    case .custom: return .balanced
    }
  }
}

nonisolated enum NotchHUDConfigurationPolicy {
  static let maximumMetricsPerSide = 5

  static func normalized(_ configuration: NotchHUDConfiguration) -> NotchHUDConfiguration {
    var result = configuration
    result.leftMetrics = unique(result.leftMetrics)
    result.rightMetrics = unique(result.rightMetrics).filter { !result.leftMetrics.contains($0) }
    result.leftMetrics = Array(result.leftMetrics.prefix(maximumMetricsPerSide))
    result.rightMetrics = Array(result.rightMetrics.prefix(maximumMetricsPerSide))

    if result.leftMetrics.isEmpty { result.showLeftPanel = false }
    if result.rightMetrics.isEmpty { result.showRightPanel = false }

    result.leftVisibleCount = clampedVisibleCount(
      result.leftVisibleCount,
      available: result.leftMetrics.count)
    result.rightVisibleCount = clampedVisibleCount(
      result.rightVisibleCount,
      available: result.rightMetrics.count)
    result.backgroundOpacity = min(max(result.backgroundOpacity, 0.2), 0.95)
    return result
  }

  static func setting(
    _ metric: MenuMetric,
    side: NotchHUDSide?,
    in configuration: NotchHUDConfiguration
  ) -> NotchHUDConfiguration {
    var result = configuration
    result.leftMetrics.removeAll { $0 == metric }
    result.rightMetrics.removeAll { $0 == metric }

    switch side {
    case .left:
      result.leftMetrics.append(metric)
      result.showLeftPanel = true
      result.leftVisibleCount = min(
        max(result.leftVisibleCount, 1),
        min(result.leftMetrics.count, maximumMetricsPerSide))
    case .right:
      result.rightMetrics.append(metric)
      result.showRightPanel = true
      result.rightVisibleCount = min(
        max(result.rightVisibleCount, 1),
        min(result.rightMetrics.count, maximumMetricsPerSide))
    case nil:
      break
    }

    return normalized(result)
  }

  static func moving(
    _ metric: MenuMetric,
    towardStart: Bool,
    in configuration: NotchHUDConfiguration
  ) -> NotchHUDConfiguration {
    var result = configuration
    if let index = result.leftMetrics.firstIndex(of: metric) {
      let destination = towardStart ? index - 1 : index + 1
      guard result.leftMetrics.indices.contains(destination) else { return result }
      result.leftMetrics.swapAt(index, destination)
    } else if let index = result.rightMetrics.firstIndex(of: metric) {
      let destination = towardStart ? index - 1 : index + 1
      guard result.rightMetrics.indices.contains(destination) else { return result }
      result.rightMetrics.swapAt(index, destination)
    }
    return normalized(result)
  }

  static func resolvedPreset(for configuration: NotchHUDConfiguration) -> NotchHUDPreset {
    let normalizedConfiguration = normalized(configuration)
    for preset in [NotchHUDPreset.minimal, .balanced, .detailed]
    where normalized(preset.configuration) == normalizedConfiguration {
      return preset
    }
    return .custom
  }

  private static func unique(_ metrics: [MenuMetric]) -> [MenuMetric] {
    var seen = Set<MenuMetric>()
    return metrics.filter { seen.insert($0).inserted }
  }

  private static func clampedVisibleCount(_ count: Int, available: Int) -> Int {
    guard available > 0 else { return 1 }
    return min(max(count, 1), min(available, maximumMetricsPerSide))
  }
}

nonisolated enum NotchHUDConfigurationPersistence {
  static let currentSchemaVersion = 1

  private struct StoredConfiguration: Codable {
    let schemaVersion: Int
    let configuration: NotchHUDConfiguration
  }

  static func encode(_ configuration: NotchHUDConfiguration) -> Data? {
    try? JSONEncoder().encode(
      StoredConfiguration(
        schemaVersion: currentSchemaVersion,
        configuration: NotchHUDConfigurationPolicy.normalized(configuration)))
  }

  static func decode(_ data: Data) -> NotchHUDConfiguration? {
    guard let stored = try? JSONDecoder().decode(StoredConfiguration.self, from: data),
      stored.schemaVersion == currentSchemaVersion
    else { return nil }
    return NotchHUDConfigurationPolicy.normalized(stored.configuration)
  }
}