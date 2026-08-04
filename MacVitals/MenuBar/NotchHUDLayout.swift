import AppKit

nonisolated struct NotchHUDHardwareGeometry: Equatable {
  let centerX: CGFloat
  let width: CGFloat
}

nonisolated struct NotchHUDScreenGeometry: Equatable {
  let safeAreaTop: CGFloat
  let notch: NotchHUDHardwareGeometry?
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
  static let edgeMargin: CGFloat = 8
  static let minimumContourClearance: CGFloat = 0
  static let maximumIndicatorLineThickness: CGFloat = 6

  static func resolvedSafeAreaTop(_ safeAreaTop: CGFloat) -> CGFloat {
    guard safeAreaTop.isFinite, safeAreaTop > 0 else { return minimumSafeAreaTop }
    return safeAreaTop
  }

  static func hardwareNotchGeometry(
    screenFrame: NSRect,
    safeAreaTop: CGFloat,
    auxiliaryTopLeftArea: NSRect?,
    auxiliaryTopRightArea: NSRect?
  ) -> NotchHUDHardwareGeometry? {
    guard safeAreaTop.isFinite,
      safeAreaTop > 0,
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

  @MainActor
  static func screenGeometry(for screen: NSScreen) -> NotchHUDScreenGeometry {
    let rawSafeAreaTop = screen.safeAreaInsets.top
    guard rawSafeAreaTop.isFinite, rawSafeAreaTop > 0 else {
      return NotchHUDScreenGeometry(safeAreaTop: 0, notch: nil)
    }

    guard let rawNotch = hardwareNotchGeometry(
      screenFrame: screen.frame,
      safeAreaTop: rawSafeAreaTop,
      auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
      auxiliaryTopRightArea: screen.auxiliaryTopRightArea)
    else {
      return NotchHUDScreenGeometry(safeAreaTop: rawSafeAreaTop, notch: nil)
    }

    let cutoutRect = NSRect(
      x: rawNotch.centerX - rawNotch.width / 2,
      y: screen.frame.maxY - rawSafeAreaTop,
      width: rawNotch.width,
      height: rawSafeAreaTop)
    let backingRect = screen.convertRectToBacking(cutoutRect)
    let alignedBackingRect = outwardIntegralBackingRect(backingRect)
    let alignedScreenRect = screen.convertRectFromBacking(alignedBackingRect)
    let clippedRect = alignedScreenRect.intersection(screen.frame)

    guard !clippedRect.isNull,
      clippedRect.width.isFinite,
      clippedRect.height.isFinite,
      clippedRect.width > 0,
      clippedRect.height > 0
    else {
      return NotchHUDScreenGeometry(safeAreaTop: rawSafeAreaTop, notch: rawNotch)
    }

    return NotchHUDScreenGeometry(
      safeAreaTop: screen.frame.maxY - clippedRect.minY,
      notch: NotchHUDHardwareGeometry(
        centerX: clippedRect.midX,
        width: clippedRect.width))
  }

  static func outwardIntegralBackingRect(_ rect: NSRect) -> NSRect {
    guard rect.minX.isFinite,
      rect.minY.isFinite,
      rect.maxX.isFinite,
      rect.maxY.isFinite
    else {
      return .zero
    }

    let minX = floor(rect.minX)
    let minY = floor(rect.minY)
    let maxX = ceil(rect.maxX)
    let maxY = ceil(rect.maxY)
    return NSRect(
      x: minX,
      y: minY,
      width: max(0, maxX - minX),
      height: max(0, maxY - minY))
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
    let maximumWidth = max(1, screenFrame.width - edgeMargin * 2)
    let minimumWidth = min(hardwareNotchWidth, maximumWidth)
    let width = min(max(preferredWidth, minimumWidth), maximumWidth)
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

    // Expand the centerline by half the stroke width. The visible inner stroke edge then
    // follows the pixel-aligned hardware cutout without drawing beneath the camera housing.
    let notchLeft = max(halfLine, hardwareNotchLeft - halfLine)
    let notchRight = min(size.width - halfLine, hardwareNotchRight + halfLine)
    let desiredBottomY = resolvedTop + minimumContourClearance + halfLine
    let maximumBottomY = size.height - halfLine - 1
    let bottomY = min(maximumBottomY, desiredBottomY)
    let verticalDepth = max(0, bottomY - 0.5)
    let adaptiveRadius = resolvedTop * 0.32
    let shoulderRadius = min(
      max(7, adaptiveRadius),
      verticalDepth * 0.46,
      resolvedNotchWidth * 0.12,
      16)

    return NotchHUDContourGeometry(
      topY: 0.5,
      bottomY: bottomY,
      notchLeftX: notchLeft,
      notchRightX: notchRight,
      shoulderRadius: max(0, shoulderRadius))
  }

  static func hardwareCutoutRect(
    in size: CGSize,
    contourGeometry: NotchHUDContourGeometry,
    lineThickness: CGFloat
  ) -> CGRect {
    let resolvedLineThickness = min(max(lineThickness, 1), maximumIndicatorLineThickness)
    let halfLine = resolvedLineThickness / 2
    let left = min(max(contourGeometry.notchLeftX + halfLine, 0), size.width)
    let right = min(max(contourGeometry.notchRightX - halfLine, left), size.width)
    let bottom = min(max(contourGeometry.bottomY - halfLine, 0), size.height)

    return CGRect(
      x: left,
      y: 0,
      width: max(0, right - left),
      height: bottom)
  }
}
