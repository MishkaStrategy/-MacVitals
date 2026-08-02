import AppKit

nonisolated struct NotchHUDContourGeometry: Equatable {
  let topY: CGFloat
  let bottomY: CGFloat
  let notchLeftX: CGFloat
  let notchRightX: CGFloat
  let shoulderRadius: CGFloat
}

nonisolated enum NotchHUDLayout {
  static let notchWidth: CGFloat = 212
  static let minimumSafeAreaTop: CGFloat = 30
  static let maximumSafeAreaTop: CGFloat = 44
  static let edgeMargin: CGFloat = 8

  static func resolvedSafeAreaTop(_ safeAreaTop: CGFloat) -> CGFloat {
    guard safeAreaTop > 0 else { return minimumSafeAreaTop }
    return min(max(safeAreaTop, minimumSafeAreaTop), maximumSafeAreaTop)
  }

  static func preferredPanelWidth(configuration: NotchHUDConfiguration) -> CGFloat {
    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    return notchWidth + CGFloat(normalized.horizontalExtension * 2)
  }

  static func preferredPanelHeight(
    safeAreaTop: CGFloat,
    configuration: NotchHUDConfiguration
  ) -> CGFloat {
    resolvedSafeAreaTop(safeAreaTop) + (configuration.showValueText ? 30 : 8)
  }

  static func panelFrame(
    for screenFrame: NSRect,
    safeAreaTop: CGFloat,
    configuration: NotchHUDConfiguration
  ) -> NSRect {
    let preferredWidth = preferredPanelWidth(configuration: configuration)
    let width = min(preferredWidth, max(notchWidth, screenFrame.width - edgeMargin * 2))
    let height = preferredPanelHeight(safeAreaTop: safeAreaTop, configuration: configuration)
    return NSRect(
      x: screenFrame.midX - width / 2,
      y: screenFrame.maxY - height,
      width: width,
      height: height)
  }

  static func contourGeometry(
    in size: CGSize,
    safeAreaTop: CGFloat
  ) -> NotchHUDContourGeometry {
    let resolvedTop = resolvedSafeAreaTop(safeAreaTop)
    let resolvedNotchWidth = min(notchWidth, max(120, size.width - 72))
    let notchLeft = (size.width - resolvedNotchWidth) / 2
    let notchRight = notchLeft + resolvedNotchWidth
    return NotchHUDContourGeometry(
      topY: 3,
      bottomY: max(20, resolvedTop - 3),
      notchLeftX: notchLeft,
      notchRightX: notchRight,
      shoulderRadius: min(20, max(12, resolvedTop * 0.48)))
  }
}
