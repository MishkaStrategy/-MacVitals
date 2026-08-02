import AppKit

nonisolated struct NotchHUDSideFrames: Equatable {
  let left: NSRect
  let right: NSRect
}

nonisolated enum NotchHUDLayout {
  static let notchHalfWidth: CGFloat = 106
  static let notchGap: CGFloat = 4
  static let edgeMargin: CGFloat = 8
  static let minimumPanelWidth: CGFloat = 72

  static func caffeinateButtonDiameter(
    configuration: NotchHUDConfiguration
  ) -> CGFloat {
    min(22, max(18, CGFloat(configuration.density.panelHeight) - 6))
  }

  static func caffeinateButtonSide(
    in configuration: NotchHUDConfiguration
  ) -> NotchHUDSide? {
    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    if normalized.showRightPanel { return .right }
    if normalized.showLeftPanel { return .left }
    return nil
  }

  static func preferredTileWidth(
    metric: MenuMetric,
    configuration: NotchHUDConfiguration
  ) -> CGFloat {
    let tile = configuration.tileConfiguration(for: metric)
    let showsLabel = tile.contentStyle.showsLabel(globalShowsLabels: configuration.showLabels)
    let showsIcon = tile.contentStyle.showsIcon(globalShowsLabels: configuration.showLabels)
    let density = configuration.density

    var base = showsLabel
      ? CGFloat(density.labeledMetricWidth)
      : CGFloat(density.metricWidth)
    if !showsIcon { base -= 10 }
    if !showsLabel, !showsIcon { base -= 8 }

    switch tile.size {
    case .automatic, .regular:
      return max(38, base)
    case .compact:
      return max(38, base - 18)
    case .wide:
      return base + 30
    }
  }

  static func preferredPanelWidth(
    metrics: [MenuMetric],
    configuration: NotchHUDConfiguration,
    includesCaffeinateButton: Bool = false
  ) -> CGFloat {
    guard !metrics.isEmpty || includesCaffeinateButton else { return minimumPanelWidth }

    let spacing = CGFloat(configuration.density.itemSpacing)
    let separators = configuration.showSeparators ? CGFloat(max(0, metrics.count - 1)) : 0
    let tilesWidth = metrics.reduce(CGFloat.zero) {
      $0 + preferredTileWidth(metric: $1, configuration: configuration)
    }
    let buttonWidth = includesCaffeinateButton
      ? caffeinateButtonDiameter(configuration: configuration)
        + (!metrics.isEmpty ? spacing : 0)
      : 0
    let contentWidth = tilesWidth
      + CGFloat(max(0, metrics.count - 1)) * spacing
      + separators
      + buttonWidth
      + CGFloat(configuration.density.horizontalPadding * 2)
    return max(minimumPanelWidth, contentWidth.rounded(.up))
  }

  static func preferredPanelWidth(
    metricCount: Int,
    configuration: NotchHUDConfiguration,
    includesCaffeinateButton: Bool = false
  ) -> CGFloat {
    guard metricCount > 0 || includesCaffeinateButton else { return minimumPanelWidth }

    let density = configuration.density
    let itemWidth = configuration.showLabels
      ? CGFloat(density.labeledMetricWidth)
      : CGFloat(density.metricWidth)
    let spacing = CGFloat(density.itemSpacing)
    let separators = configuration.showSeparators ? CGFloat(max(0, metricCount - 1)) : 0
    let buttonWidth = includesCaffeinateButton
      ? caffeinateButtonDiameter(configuration: configuration)
        + (metricCount > 0 ? spacing : 0)
      : 0
    let contentWidth = CGFloat(metricCount) * itemWidth
      + CGFloat(max(0, metricCount - 1)) * spacing
      + separators
      + buttonWidth
      + CGFloat(density.horizontalPadding * 2)
    return max(minimumPanelWidth, contentWidth.rounded(.up))
  }

  static func sideFrames(
    for screenFrame: NSRect,
    safeAreaTop: CGFloat,
    configuration: NotchHUDConfiguration = .balanced
  ) -> NotchHUDSideFrames {
    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    let panelHeight = CGFloat(normalized.density.panelHeight)
    let menuBarHeight = safeAreaTop > 0
      ? min(max(safeAreaTop, panelHeight), 40)
      : max(30, panelHeight)
    let y = screenFrame.maxY - menuBarHeight
      + max(0, (menuBarHeight - panelHeight) / 2)

    let halfClearance = safeAreaTop > 0 ? notchHalfWidth : 8
    let leftBoundary = screenFrame.midX - halfClearance - notchGap
    let rightBoundary = screenFrame.midX + halfClearance + notchGap
    let caffeinateSide = caffeinateButtonSide(in: normalized)
    let leftMetrics = normalized.metrics(for: .left)
    let rightMetrics = normalized.metrics(for: .right)

    let preferredLeftWidth = preferredPanelWidth(
      metrics: leftMetrics,
      configuration: normalized,
      includesCaffeinateButton: caffeinateSide == .left)
    let preferredRightWidth = preferredPanelWidth(
      metrics: rightMetrics,
      configuration: normalized,
      includesCaffeinateButton: caffeinateSide == .right)
    let maximumLeftWidth = max(minimumPanelWidth, leftBoundary - screenFrame.minX - edgeMargin)
    let maximumRightWidth = max(
      minimumPanelWidth,
      screenFrame.maxX - edgeMargin - rightBoundary)
    let resolvedLeftWidth = min(preferredLeftWidth, maximumLeftWidth)
    let resolvedRightWidth = min(preferredRightWidth, maximumRightWidth)

    let left = NSRect(
      x: max(screenFrame.minX + edgeMargin, leftBoundary - resolvedLeftWidth),
      y: y,
      width: resolvedLeftWidth,
      height: panelHeight)
    let right = NSRect(
      x: min(rightBoundary, screenFrame.maxX - edgeMargin - resolvedRightWidth),
      y: y,
      width: resolvedRightWidth,
      height: panelHeight)

    return NotchHUDSideFrames(left: left, right: right)
  }
}
