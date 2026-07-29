import AppKit
import Foundation

nonisolated struct MenuBarStatusSegment: Equatable {
  let metric: MenuMetric
  let state: MenuBarIconState
  let value: String
}

private struct MenuBarStatusSegmentLayout {
  let icon: NSImage?
  let value: String
  let valueAttributes: [NSAttributedString.Key: Any]
  let valueSize: NSSize
  let iconWidth: CGFloat
  let totalWidth: CGFloat
}

nonisolated enum MenuBarStatusTitleRenderer {
  static func segments(
    snapshot: SystemSnapshot,
    metrics: [MenuMetric]
  ) -> [MenuBarStatusSegment] {
    MenuLayoutRules.normalized(metrics).map { metric in
      MenuBarStatusSegment(
        metric: metric,
        state: MenuBarIconCatalog.state(for: metric, snapshot: snapshot),
        value: compactValue(for: metric, snapshot: snapshot))
    }
  }

  static func compactText(
    snapshot: SystemSnapshot,
    metrics: [MenuMetric]
  ) -> String {
    segments(snapshot: snapshot, metrics: metrics)
      .map(\.value)
      .joined(separator: "   ")
  }

  @MainActor
  static func lightImage(
    snapshot: SystemSnapshot,
    metrics: [MenuMetric]
  ) -> NSImage {
    let resolvedSegments = segments(snapshot: snapshot, metrics: metrics)
    let drawableSegments = resolvedSegments.isEmpty
      ? [MenuBarStatusSegment(metric: .cpu, state: .normal, value: "")]
      : resolvedSegments

    let iconTextGap: CGFloat = 2
    let segmentGap: CGFloat = 8
    let horizontalPadding: CGFloat = 1
    let canvasHeight: CGFloat = 18

    let layouts = drawableSegments.map { segment -> MenuBarStatusSegmentLayout in
      let icon = lightMaskImage(for: segment.metric, state: segment.state)
      let attributes = valueAttributes(for: segment.state)
      let valueSize = (segment.value as NSString).size(withAttributes: attributes)
      let iconWidth = icon?.size.width ?? 3
      let valueWidth = segment.value.isEmpty ? 0 : ceil(valueSize.width)
      let totalWidth = iconWidth + (segment.value.isEmpty ? 0 : iconTextGap + valueWidth)

      return MenuBarStatusSegmentLayout(
        icon: icon,
        value: segment.value,
        valueAttributes: attributes,
        valueSize: valueSize,
        iconWidth: iconWidth,
        totalWidth: totalWidth)
    }

    let contentWidth = layouts.reduce(CGFloat.zero) { $0 + $1.totalWidth }
      + segmentGap * CGFloat(max(0, layouts.count - 1))
    let imageSize = NSSize(
      width: max(12, ceil(contentWidth + horizontalPadding * 2)),
      height: canvasHeight)

    let backingScale: CGFloat = 2
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(ceil(imageSize.width * backingScale)),
        pixelsHigh: Int(ceil(imageSize.height * backingScale)),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0),
      let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
      return fallbackLightImage()
    }

    bitmap.size = imageSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    graphicsContext.cgContext.scaleBy(x: backingScale, y: backingScale)
    graphicsContext.cgContext.clear(CGRect(origin: .zero, size: imageSize))
    graphicsContext.imageInterpolation = .high

    var x = horizontalPadding
    for (index, layout) in layouts.enumerated() {
      if let icon = layout.icon {
        let iconRect = NSRect(
          x: x,
          y: floor((imageSize.height - icon.size.height) / 2),
          width: icon.size.width,
          height: icon.size.height)
        icon.draw(in: iconRect)
      } else {
        let fallbackAttributes: [NSAttributedString.Key: Any] = [
          .font: NSFont.systemFont(ofSize: 9, weight: .medium),
          .foregroundColor: NSColor.white,
        ]
        let fallback = "·" as NSString
        let fallbackSize = fallback.size(withAttributes: fallbackAttributes)
        fallback.draw(
          at: NSPoint(
            x: x,
            y: floor((imageSize.height - fallbackSize.height) / 2)),
          withAttributes: fallbackAttributes)
      }

      x += layout.iconWidth

      if !layout.value.isEmpty {
        x += iconTextGap
        (layout.value as NSString).draw(
          at: NSPoint(
            x: x,
            y: floor((imageSize.height - layout.valueSize.height) / 2) - 0.5),
          withAttributes: layout.valueAttributes)
        x += ceil(layout.valueSize.width)
      }

      if index < layouts.count - 1 {
        x += segmentGap
      }
    }

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: imageSize)
    image.addRepresentation(bitmap)
    // Keep the complete surface physically white and non-template. This prevents
    // NSStatusBarButton from recoloring it black on affected macOS 26 configurations.
    image.isTemplate = false
    return image
  }

  private static func compactValue(
    for metric: MenuMetric,
    snapshot: SystemSnapshot
  ) -> String {
    switch metric {
    case .cpu:
      return percentage(snapshot.cpu.value?.total).map { "\($0)%" } ?? "—"
    case .gpu:
      return percentage(snapshot.gpu.value?.systemUtilizationPercent).map { "\($0)%" } ?? "—"
    case .memory:
      return percentage(snapshot.memory.value?.usedPercent).map { "\($0)%" } ?? "—"
    case .temperature:
      return temperatureSummary(snapshot.temperature.value)
    case .battery:
      return percentage(snapshot.battery.value?.percentage).map { "\($0)%" } ?? "—"
    case .fans:
      return fanSummary(snapshot.fans.value?.fans)
    case .systemPower:
      return decimalWatts(snapshot.power.value?.estimatedSystemPowerWatts) ?? "—"
    case .adapterPower:
      return decimalWatts(snapshot.power.value?.adapterInputPowerWatts)
        ?? snapshot.adapter.value?.ratedPowerWatts.flatMap { boundedInteger($0, range: 0...10_000) }
          .map { "≤\($0)W" }
        ?? "—"
    case .powerStatus:
      return powerStatus(snapshot.power.value?.status)
    }
  }

  private static func temperatureSummary(_ stats: TemperatureStats?) -> String {
    guard let stats else { return "—" }
    let processor = temperature(stats.processorCelsius)
    let battery = temperature(stats.batteryCelsius)

    switch (processor, battery) {
    case (.some(let cpu), .some(let battery)):
      return "\(cpu)°/\(battery)°"
    case (.some(let cpu), .none):
      return "\(cpu)°"
    case (.none, .some(let battery)):
      return "\(battery)°"
    case (.none, .none):
      return "—"
    }
  }

  private static func fanSummary(_ fans: [FanReading]?) -> String {
    guard let fans, !fans.isEmpty else { return "—" }

    let values = fans.prefix(2).compactMap { fan -> Int? in
      guard let rpm = fan.currentRPM else { return nil }
      return boundedInteger(rpm, range: 0...100_000)
    }

    return values.isEmpty ? "—" : values.map(String.init).joined(separator: "/")
  }

  private static func percentage(_ value: Double?) -> Int? {
    boundedInteger(value, range: 0...100)
  }

  private static func temperature(_ value: Double?) -> Int? {
    boundedInteger(value, range: -20...130)
  }

  private static func decimalWatts(_ value: Double?) -> String? {
    guard let value, value.isFinite, (0...10_000).contains(abs(value)) else { return nil }
    return String(format: "%.1fW", abs(value))
  }

  private static func boundedInteger(
    _ value: Double?,
    range: ClosedRange<Double>
  ) -> Int? {
    guard let value, value.isFinite, range.contains(value) else { return nil }
    return Int(value.rounded())
  }

  private static func powerStatus(_ status: PowerSufficiencyStatus?) -> String {
    switch status {
    case .insufficient: return "!"
    case .borderline: return "◐"
    case .chargingBattery: return "↯"
    case .sufficient: return "✓"
    case .notConnected: return "—"
    case .sensorConflict: return "!?"
    case .powerAdapterOnly: return "⌁"
    case .unknown, nil: return "?"
    }
  }

  @MainActor
  private static func lightMaskImage(
    for metric: MenuMetric,
    state: MenuBarIconState
  ) -> NSImage? {
    guard let source = MenuBarIconCatalog.minimalImage(for: metric, state: state) else {
      return nil
    }

    let whiteConfiguration = NSImage.SymbolConfiguration(hierarchicalColor: .white)
    let configured = source.withSymbolConfiguration(whiteConfiguration) ?? source
    let image = configured.copy() as? NSImage ?? configured
    image.size = source.size
    image.isTemplate = false
    return image
  }

  @MainActor
  private static func fallbackLightImage() -> NSImage {
    let source = MenuBarIconCatalog.minimalImage(for: .cpu, state: .normal)
      ?? NSImage(size: NSSize(width: 12, height: 18))
    let whiteConfiguration = NSImage.SymbolConfiguration(hierarchicalColor: .white)
    let configured = source.withSymbolConfiguration(whiteConfiguration) ?? source
    let image = configured.copy() as? NSImage ?? configured
    image.isTemplate = false
    return image
  }

  @MainActor
  private static func valueAttributes(
    for state: MenuBarIconState
  ) -> [NSAttributedString.Key: Any] {
    let weight: NSFont.Weight
    switch state {
    case .normal: weight = .regular
    case .elevated: weight = .medium
    case .critical: weight = .semibold
    }

    return [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: weight),
      .foregroundColor: NSColor.white,
      .kern: -0.15,
    ]
  }
}
