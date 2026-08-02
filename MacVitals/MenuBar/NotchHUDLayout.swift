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

  static func preferredPanelWidth(
    metricCount: Int,
    configuration: NotchHUDConfiguration
  ) -> CGFloat {
    guard metricCount > 0 else { return minimumPanelWidth }

    let density = configuration.density
    let itemWidth = configuration.showLabels
      ? CGFloat(density.labeledMetricWidth)
      : CGFloat(density.metricWidth)
    let spacing = CGFloat(density.itemSpacing)
    let separators = configuration.showSeparators ? CGFloat(max(0, metricCount - 1)) : 0
    let contentWidth = CGFloat(metricCount) * itemWidth
      + CGFloat(max(0, metricCount - 1)) * spacing
      + separators
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

    let preferredLeftWidth = preferredPanelWidth(
      metricCount: normalized.metrics(for: .left).count,
      configuration: normalized)
    let preferredRightWidth = preferredPanelWidth(
      metricCount: normalized.metrics(for: .right).count,
      configuration: normalized)
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