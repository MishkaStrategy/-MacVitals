import AppKit

nonisolated struct NotchHUDHardwareGeometry: Equatable {
  let centerX: CGFloat
  let width: CGFloat
}

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
  static let minimumContourClearance: CGFloat = 0
  static let maximumIndicatorLineThickness: CGFloat = 6

  static func resolvedSafeAreaTop(_ safeAreaTop: CGFloat) -> CGFloat {
    guard safeAreaTop > 0 else { return minimumSafeAreaTop }
    return min(max(safeAreaTop, minimumSafeAreaTop), maximumSafeAreaTop)
  }

  static func hardwareNotchGeometry(
    screenFrame: NSRect,
    safeAreaTop: CGFloat,
    auxiliaryTopLeftArea: NSRect?,
    auxiliaryTopRightArea: NSRect?
  ) -> NotchHUDHardwareGeometry? {
    guard safeAreaTop > 0,
      let leftArea = auxiliaryTopLeftArea,
      let rightArea = auxiliaryTopRightArea
    else {
      return nil
    }

    let leftEdge = leftArea.maxX
    let rightEdge = rightArea.minX
    let width = rightEdge - leftEdge
    let tolerance: CGFloat = 1

    guard leftEdge.isFinite,
      rightEdge.isFinite,
      width.isFinite,
      width > 0,
      leftEdge >= screenFrame.minX - tolerance,
      rightEdge <= screenFrame.maxX + tolerance,
      width <= screenFrame.width
    else {
      return nil
    }

    return NotchHUDHardwareGeometry(
      centerX: (leftEdge + rightEdge) / 2,
      width: width)
  }

  static func preferredPanelWidth(
    configuration: NotchHUDConfiguration,
    notchWidth: CGFloat = notchWidth
  ) -> CGFloat {
    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    let resolvedWidth = notchWidth.isFinite && notchWidth > 0 ? notchWidth : Self.notchWidth
    return resolvedWidth + CGFloat(normalized.horizontalExtension * 2)
  }

  static func preferredPanelHeight(
    safeAreaTop: CGFloat,
    configuration: NotchHUDConfiguration
  ) -> CGFloat {
    resolvedSafeAreaTop(safeAreaTop) + (configuration.showValueText ? 32 : 20)
  }

  static func panelFrame(
    for screenFrame: NSRect,
    safeAreaTop: CGFloat,
    configuration: NotchHUDConfiguration,
    notchGeometry: NotchHUDHardwareGeometry? = nil
  ) -> NSRect {
    let hardwareNotchWidth = notchGeometry?.width ?? notchWidth
    let preferredWidth = preferredPanelWidth(
      configuration: configuration,
      notchWidth: hardwareNotchWidth)
    let maximumWidth = max(notchWidth, screenFrame.width - edgeMargin * 2)
    let width = min(preferredWidth, maximumWidth)
    let centerX = notchGeometry?.centerX ?? screenFrame.midX
    let minimumX = screenFrame.minX + edgeMargin
    let maximumX = screenFrame.maxX - edgeMargin - width
    let x = min(max(centerX - width / 2, minimumX), max(minimumX, maximumX))
    let height = preferredPanelHeight(safeAreaTop: safeAreaTop, configuration: configuration)

    return NSRect(
      x: x,
      y: screenFrame.maxY - height,
      width: width,
      height: height)
  }

  static func contourGeometry(
    in size: CGSize,
    safeAreaTop: CGFloat,
    lineThickness: CGFloat = maximumIndicatorLineThickness,
    notchWidth: CGFloat = notchWidth
  ) -> NotchHUDContourGeometry {
    let resolvedTop = resolvedSafeAreaTop(safeAreaTop)
    let resolvedLineThickness = min(max(lineThickness, 1), maximumIndicatorLineThickness)
    let maximumHardwareWidth = max(1, size.width - resolvedLineThickness - 2)
    let candidateNotchWidth = notchWidth.isFinite && notchWidth > 0 ? notchWidth : Self.notchWidth
    let resolvedNotchWidth = min(candidateNotchWidth, maximumHardwareWidth)
    let hardwareNotchLeft = (size.width - resolvedNotchWidth) / 2
    let hardwareNotchRight = hardwareNotchLeft + resolvedNotchWidth
    let halfLine = resolvedLineThickness / 2

    // The centerline is expanded by half the stroke width so the visible inner edge
    // touches the physical cutout exactly without drawing underneath it.
    let notchLeft = max(halfLine, hardwareNotchLeft - halfLine)
    let notchRight = min(size.width - halfLine, hardwareNotchRight + halfLine)
    let desiredBottomY = resolvedTop + minimumContourClearance + halfLine
    let maximumBottomY = size.height - halfLine - 1
    let bottomY = min(maximumBottomY, desiredBottomY)

    return NotchHUDContourGeometry(
      topY: 0.5,
      bottomY: bottomY,
      notchLeftX: notchLeft,
      notchRightX: notchRight,
      shoulderRadius: min(14, max(9, resolvedTop * 0.30)))
  }
}
