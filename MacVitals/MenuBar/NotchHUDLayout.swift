import AppKit

nonisolated struct NotchHUDSideFrames: Equatable {
  let left: NSRect
  let right: NSRect
}

nonisolated enum NotchHUDLayout {
  static let panelHeight: CGFloat = 28
  static let leftPanelWidth: CGFloat = 250
  static let rightPanelWidth: CGFloat = 322
  static let notchHalfWidth: CGFloat = 106
  static let notchGap: CGFloat = 4
  static let edgeMargin: CGFloat = 8

  static func sideFrames(
    for screenFrame: NSRect,
    safeAreaTop: CGFloat
  ) -> NotchHUDSideFrames {
    let menuBarHeight = safeAreaTop > 0
      ? min(max(safeAreaTop, panelHeight), 40)
      : 30
    let y = screenFrame.maxY - menuBarHeight
      + max(0, (menuBarHeight - panelHeight) / 2)

    let halfClearance = safeAreaTop > 0 ? notchHalfWidth : 8
    let leftBoundary = screenFrame.midX - halfClearance - notchGap
    let rightBoundary = screenFrame.midX + halfClearance + notchGap

    let maximumLeftWidth = max(96, leftBoundary - screenFrame.minX - edgeMargin)
    let maximumRightWidth = max(112, screenFrame.maxX - edgeMargin - rightBoundary)
    let resolvedLeftWidth = min(leftPanelWidth, maximumLeftWidth)
    let resolvedRightWidth = min(rightPanelWidth, maximumRightWidth)

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
