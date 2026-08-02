import AppKit

nonisolated enum NotchHUDLayout {
  static let railHeight: CGFloat = 38
  static let detailSize = NSSize(width: 348, height: 176)
  static let detailGap: CGFloat = 7

  static func railFrame(
    for screenFrame: NSRect,
    safeAreaTop: CGFloat
  ) -> NSRect {
    let horizontalMargin = min(max(screenFrame.width * 0.035, 28), 72)
    let width = max(560, min(1_240, screenFrame.width - horizontalMargin * 2))
    let topInset = max(railHeight, safeAreaTop)

    return NSRect(
      x: screenFrame.midX - width / 2,
      y: screenFrame.maxY - topInset,
      width: width,
      height: railHeight)
  }

  static func detailFrame(
    below railFrame: NSRect,
    screenFrame: NSRect
  ) -> NSRect {
    let proposed = NSRect(
      x: railFrame.midX - detailSize.width / 2,
      y: railFrame.minY - detailSize.height - detailGap,
      width: detailSize.width,
      height: detailSize.height)

    let minimumX = screenFrame.minX + 12
    let maximumX = screenFrame.maxX - detailSize.width - 12

    return NSRect(
      x: min(max(proposed.minX, minimumX), maximumX),
      y: max(proposed.minY, screenFrame.minY + 12),
      width: detailSize.width,
      height: detailSize.height)
  }
}
