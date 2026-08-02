import Foundation

nonisolated enum NotchHUDTileSize: String, Codable, CaseIterable, Identifiable, Sendable {
  case automatic, compact, regular, wide
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .automatic: return L10n.string("Automatic")
    case .compact: return L10n.string("Compact")
    case .regular: return L10n.string("Regular")
    case .wide: return L10n.string("Wide")
    }
  }
}

nonisolated enum NotchHUDTileContentStyle: String, Codable, CaseIterable, Identifiable, Sendable {
  case automatic, iconValue, labelValue, iconLabelValue, valueOnly
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .automatic: return L10n.string("Automatic")
    case .iconValue: return L10n.string("Icon and value")
    case .labelValue: return L10n.string("Label and value")
    case .iconLabelValue: return L10n.string("Icon, label and value")
    case .valueOnly: return L10n.string("Value only")
    }
  }

  func showsIcon(globalShowsLabels _: Bool) -> Bool {
    switch self {
    case .automatic, .iconValue, .iconLabelValue: return true
    case .labelValue, .valueOnly: return false
    }
  }

  func showsLabel(globalShowsLabels: Bool) -> Bool {
    switch self {
    case .automatic: return globalShowsLabels
    case .labelValue, .iconLabelValue: return true
    case .iconValue, .valueOnly: return false
    }
  }
}

nonisolated enum NotchHUDTileAlignment: String, Codable, CaseIterable, Identifiable, Sendable {
  case leading, center, trailing
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .leading: return L10n.string("Leading")
    case .center: return L10n.string("Center")
    case .trailing: return L10n.string("Trailing")
    }
  }
}

nonisolated enum NotchHUDTileEmphasis: String, Codable, CaseIterable, Identifiable, Sendable {
  case muted, normal, prominent
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .muted: return L10n.string("Muted")
    case .normal: return L10n.string("Normal")
    case .prominent: return L10n.string("Prominent")
    }
  }
  var scale: Double {
    switch self {
    case .muted: return 0.92
    case .normal: return 1
    case .prominent: return 1.12
    }
  }
}

nonisolated enum NotchHUDTilePrecision: String, Codable, CaseIterable, Identifiable, Sendable {
  case automatic, zero, one, two
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .automatic: return L10n.string("Automatic")
    case .zero: return L10n.string("0 decimals")
    case .one: return L10n.string("1 decimal")
    case .two: return L10n.string("2 decimals")
    }
  }
  var fractionDigits: Int? {
    switch self {
    case .automatic: return nil
    case .zero: return 0
    case .one: return 1
    case .two: return 2
    }
  }
}

nonisolated enum NotchHUDTileColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case inherited, monochrome, accent, semantic, custom
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .inherited: return L10n.string("Inherited")
    case .monochrome: return L10n.string("Monochrome")
    case .accent: return L10n.string("Accent color")
    case .semantic: return L10n.string("Threshold colors")
    case .custom: return L10n.string("Custom color")
    }
  }
}

nonisolated enum NotchHUDTileAccent: String, Codable, CaseIterable, Identifiable, Sendable {
  case white, blue, cyan, green, yellow, orange, red, pink, purple
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .white: return L10n.string("White")
    case .blue: return L10n.string("Blue")
    case .cyan: return L10n.string("Cyan")
    case .green: return L10n.string("Green")
    case .yellow: return L10n.string("Yellow")
    case .orange: return L10n.string("Orange")
    case .red: return L10n.string("Red")
    case .pink: return L10n.string("Pink")
    case .purple: return L10n.string("Purple")
    }
  }
}

nonisolated enum NotchHUDTileBackgroundStyle: String, Codable, CaseIterable, Identifiable, Sendable {
  case none, subtle, filled, outline
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .none: return L10n.string("None")
    case .subtle: return L10n.string("Subtle")
    case .filled: return L10n.string("Filled")
    case .outline: return L10n.string("Outline")
    }
  }
}

nonisolated enum NotchHUDThresholdDirection: String, Codable, CaseIterable, Identifiable, Sendable {
  case highIsCritical, lowIsCritical
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .highIsCritical: return L10n.string("Higher is worse")
    case .lowIsCritical: return L10n.string("Lower is worse")
    }
  }
}

nonisolated enum NotchHUDTileSemanticState: Sendable {
  case normal, warning, critical, unavailable
}

nonisolated struct NotchHUDTileConfiguration: Codable, Equatable, Sendable {
  var size: NotchHUDTileSize
  var contentStyle: NotchHUDTileContentStyle
  var alignment: NotchHUDTileAlignment
  var emphasis: NotchHUDTileEmphasis
  var customLabel: String
  var symbolName: String
  var precision: NotchHUDTilePrecision
  var showsUnit: Bool
  var colorMode: NotchHUDTileColorMode
  var accent: NotchHUDTileAccent
  var backgroundStyle: NotchHUDTileBackgroundStyle
  var backgroundOpacity: Double
  var warningThreshold: Double
  var criticalThreshold: Double
  var thresholdDirection: NotchHUDThresholdDirection

  static func defaultConfiguration(for metric: MenuMetric) -> NotchHUDTileConfiguration {
    let thresholds: (Double, Double, NotchHUDThresholdDirection)
    switch metric {
    case .cpu, .gpu: thresholds = (70, 90, .highIsCritical)
    case .memory: thresholds = (75, 90, .highIsCritical)
    case .temperature: thresholds = (75, 90, .highIsCritical)
    case .battery: thresholds = (25, 10, .lowIsCritical)
    case .fans: thresholds = (4_000, 6_000, .highIsCritical)
    case .systemPower: thresholds = (40, 80, .highIsCritical)
    case .adapterPower: thresholds = (45, 90, .highIsCritical)
    case .powerStatus: thresholds = (70, 90, .highIsCritical)
    }

    return NotchHUDTileConfiguration(
      size: .automatic,
      contentStyle: .automatic,
      alignment: .center,
      emphasis: .normal,
      customLabel: "",
      symbolName: metric.defaultSymbol,
      precision: .automatic,
      showsUnit: true,
      colorMode: .inherited,
      accent: .blue,
      backgroundStyle: .none,
      backgroundOpacity: 0.18,
      warningThreshold: thresholds.0,
      criticalThreshold: thresholds.1,
      thresholdDirection: thresholds.2)
  }
}

nonisolated enum NotchHUDTileConfigurationPolicy {
  static func normalized(
    _ configuration: NotchHUDTileConfiguration,
    for metric: MenuMetric
  ) -> NotchHUDTileConfiguration {
    var result = configuration
    result.customLabel = String(
      result.customLabel.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
    result.symbolName = result.symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
    if result.symbolName.isEmpty { result.symbolName = metric.defaultSymbol }
    result.backgroundOpacity = min(max(result.backgroundOpacity, 0), 1)
    result.warningThreshold = min(max(result.warningThreshold, -999), 99_999)
    result.criticalThreshold = min(max(result.criticalThreshold, -999), 99_999)

    switch result.thresholdDirection {
    case .highIsCritical where result.warningThreshold > result.criticalThreshold:
      let previousWarning = result.warningThreshold
      result.warningThreshold = result.criticalThreshold
      result.criticalThreshold = previousWarning
    case .lowIsCritical where result.criticalThreshold > result.warningThreshold:
      let previousCritical = result.criticalThreshold
      result.criticalThreshold = result.warningThreshold
      result.warningThreshold = previousCritical
    default:
      break
    }
    return result
  }

  static func semanticState(
    renderedValue: String,
    configuration: NotchHUDTileConfiguration
  ) -> NotchHUDTileSemanticState {
    guard let value = NotchHUDTileValueFormatter.numericValue(from: renderedValue) else {
      return .unavailable
    }
    switch configuration.thresholdDirection {
    case .highIsCritical:
      if value >= configuration.criticalThreshold { return .critical }
      if value >= configuration.warningThreshold { return .warning }
    case .lowIsCritical:
      if value <= configuration.criticalThreshold { return .critical }
      if value <= configuration.warningThreshold { return .warning }
    }
    return .normal
  }
}

nonisolated enum NotchHUDTileValueFormatter {
  private static let numericExpression = try? NSRegularExpression(
    pattern: #"[-+]?\d+(?:[\.,]\d+)?"#)

  static func renderedValue(
    from rawValue: String,
    configuration: NotchHUDTileConfiguration
  ) -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let match = numericMatch(in: trimmed) else { return trimmed }
    let numericString = String(trimmed[match])
    guard let numericValue = Double(numericString.replacingOccurrences(of: ",", with: ".")) else {
      return trimmed
    }

    let formattedNumber: String
    if let digits = configuration.precision.fractionDigits {
      let formatter = NumberFormatter()
      formatter.locale = .current
      formatter.minimumFractionDigits = digits
      formatter.maximumFractionDigits = digits
      formatter.usesGroupingSeparator = false
      formattedNumber = formatter.string(from: NSNumber(value: numericValue)) ?? numericString
    } else {
      formattedNumber = numericString
    }

    guard configuration.showsUnit else { return formattedNumber }
    return formattedNumber + String(trimmed[match.upperBound...])
  }

  static func numericValue(from renderedValue: String) -> Double? {
    let trimmed = renderedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let match = numericMatch(in: trimmed) else { return nil }
    return Double(String(trimmed[match]).replacingOccurrences(of: ",", with: "."))
  }

  private static func numericMatch(in value: String) -> Range<String.Index>? {
    guard let numericExpression else { return nil }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = numericExpression.firstMatch(in: value, range: range) else { return nil }
    return Range(match.range, in: value)
  }
}

extension MenuMetric {
  nonisolated var notchHUDShortLabel: String {
    switch self {
    case .cpu: return "CPU"
    case .gpu: return "GPU"
    case .memory: return "RAM"
    case .temperature: return "TEMP"
    case .battery: return "BAT"
    case .fans: return "FAN"
    case .systemPower: return "PWR"
    case .adapterPower: return "AC"
    case .powerStatus: return "LOAD"
    }
  }

  nonisolated var notchHUDSymbolOptions: [String] {
    switch self {
    case .cpu: return ["cpu", "gauge.with.dots.needle.67percent", "chart.bar.fill"]
    case .gpu: return ["display", "rectangle.3.group", "sparkles.rectangle.stack"]
    case .memory: return ["memorychip", "square.stack.3d.up.fill", "externaldrive.fill"]
    case .temperature: return ["thermometer.medium", "thermometer.high", "flame.fill"]
    case .battery: return ["battery.100", "battery.75percent", "bolt.fill"]
    case .fans: return ["fan", "wind", "tornado"]
    case .systemPower: return ["bolt", "bolt.horizontal.fill", "waveform.path.ecg"]
    case .adapterPower: return ["powerplug", "powerplug.fill", "cable.connector"]
    case .powerStatus:
      return ["gauge.with.dots.needle.50percent", "speedometer", "chart.line.uptrend.xyaxis"]
    }
  }
}
