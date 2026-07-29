import AppKit

nonisolated enum MenuBarIconState: String, CaseIterable, Sendable {
  case normal
  case elevated
  case critical
}

nonisolated enum MenuBarIconCatalog {
  static func symbolName(for metric: MenuMetric, state: MenuBarIconState) -> String {
    switch (metric, state) {
    case (.battery, .normal): return "battery.75percent"
    case (.battery, .elevated): return "battery.25percent"
    case (.battery, .critical): return "battery.0percent"

    case (.cpu, .normal): return "cpu"
    case (.cpu, .elevated): return "cpu.fill"
    case (.cpu, .critical): return "exclamationmark.triangle.fill"

    case (.memory, .normal): return "memorychip"
    case (.memory, .elevated): return "memorychip.fill"
    case (.memory, .critical): return "exclamationmark.triangle.fill"

    case (.gpu, .normal): return "rectangle.3.group"
    case (.gpu, .elevated): return "rectangle.3.group.fill"
    case (.gpu, .critical): return "exclamationmark.triangle.fill"

    case (.temperature, .normal): return "thermometer.medium"
    case (.temperature, .elevated): return "thermometer.high"
    case (.temperature, .critical): return "thermometer.sun.fill"

    case (.fans, .normal): return "fan"
    case (.fans, .elevated): return "fan.fill"
    case (.fans, .critical): return "fan.badge.exclamationmark"

    case (.systemPower, .normal), (.adapterPower, .normal), (.powerStatus, .normal):
      return "bolt"
    case (.systemPower, .elevated), (.adapterPower, .elevated), (.powerStatus, .elevated):
      return "bolt.fill"
    case (.systemPower, .critical), (.adapterPower, .critical), (.powerStatus, .critical):
      return "exclamationmark.triangle.fill"
    }
  }

  static func minimalSymbolCandidates(
    for metric: MenuMetric,
    state: MenuBarIconState
  ) -> [String] {
    switch metric {
    case .battery:
      switch state {
      case .normal: return ["battery.75percent"]
      case .elevated: return ["battery.25percent", "battery.75percent"]
      case .critical: return ["battery.0percent", "battery.25percent"]
      }
    case .cpu:
      return ["cpu"]
    case .gpu:
      return ["gpu", "display", "rectangle.3.group"]
    case .memory:
      return ["memorychip"]
    case .temperature:
      switch state {
      case .normal: return ["thermometer.medium"]
      case .elevated, .critical: return ["thermometer.high", "thermometer.medium"]
      }
    case .fans:
      return ["fan"]
    case .systemPower:
      return ["bolt"]
    case .adapterPower:
      return ["powerplug", "bolt"]
    case .powerStatus:
      return ["bolt.circle", "bolt"]
    }
  }

  static func state(for metric: MenuMetric, snapshot: SystemSnapshot) -> MenuBarIconState {
    switch metric {
    case .cpu:
      return loadState(snapshot.cpu.value?.total, elevated: 70, critical: 90)
    case .gpu:
      return loadState(snapshot.gpu.value?.systemUtilizationPercent, elevated: 75, critical: 95)
    case .memory:
      switch snapshot.memory.value?.pressureLevel {
      case .critical: return .critical
      case .warning: return .elevated
      default: return loadState(snapshot.memory.value?.usedPercent, elevated: 80, critical: 95)
      }
    case .temperature:
      return loadState(
        snapshot.temperature.value?.maximumCelsius
          ?? snapshot.temperature.value?.processorCelsius,
        elevated: 85,
        critical: 100)
    case .battery:
      guard snapshot.battery.value?.externalPowerConnected != true else { return .normal }
      guard let percentage = snapshot.battery.value?.percentage else { return .elevated }
      if percentage <= 10 { return .critical }
      if percentage <= 25 { return .elevated }
      return .normal
    case .fans:
      guard let fans = snapshot.fans.value?.fans, !fans.isEmpty else { return .elevated }
      if fans.contains(where: { ($0.currentRPM ?? 0) <= 0 }) { return .critical }
      if fans.contains(where: { $0.mode == .manual }) { return .elevated }
      return .normal
    case .systemPower, .adapterPower, .powerStatus:
      switch snapshot.power.value?.status {
      case .insufficient, .sensorConflict: return .critical
      case .borderline, .unknown, nil: return .elevated
      default: return .normal
      }
    }
  }

  @MainActor
  static func image(for metric: MenuMetric, state: MenuBarIconState) -> NSImage? {
    let name = symbolName(for: metric, state: state)
    guard let base = NSImage(
      systemSymbolName: name,
      accessibilityDescription: metric.displayName)
    else { return nil }

    let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    let image = base.withSymbolConfiguration(configuration) ?? base
    image.isTemplate = true
    image.size = NSSize(width: 18, height: 18)
    return image
  }

  @MainActor
  static func minimalImage(for metric: MenuMetric, state: MenuBarIconState) -> NSImage? {
    let base = minimalSymbolCandidates(for: metric, state: state)
      .lazy
      .compactMap {
        NSImage(systemSymbolName: $0, accessibilityDescription: metric.displayName)
      }
      .first

    guard let base else { return nil }

    let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
    let image = base.withSymbolConfiguration(configuration) ?? base
    image.isTemplate = true

    let targetHeight: CGFloat = 11
    let sourceSize = image.size
    let aspectRatio = sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 1
    let targetWidth = min(14, max(8, targetHeight * aspectRatio))
    image.size = NSSize(width: targetWidth, height: targetHeight)
    return image
  }

  private static func loadState(
    _ value: Double?,
    elevated: Double,
    critical: Double
  ) -> MenuBarIconState {
    guard let value, value.isFinite else { return .elevated }
    if value >= critical { return .critical }
    if value >= elevated { return .elevated }
    return .normal
  }
}
