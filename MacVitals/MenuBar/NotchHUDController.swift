import AppKit
import Foundation
import SwiftUI

@MainActor
final class NotchHUDController {
  nonisolated static let defaultsKey = "experimentalNotchHUDEnabled"

  private let state = NotchHUDState()
  private var panel: NSPanel?
  private var enabled = false
  private var activeScreenNumber: NSNumber?

  var isEnabled: Bool { enabled }

  var hasAllocatedPanelsForTesting: Bool {
    panel != nil
  }

  func update(
    snapshot: SystemSnapshot,
    preferredScreen: NSScreen?,
    enabled: Bool,
    configuration: NotchHUDConfiguration = .minimal
  ) {
    self.enabled = enabled
    writeDiagnostics(event: "update", screen: preferredScreen)

    guard enabled else {
      hide(event: "disabled")
      return
    }

    state.snapshot = snapshot
    state.configuration = NotchHUDConfigurationPolicy.normalized(configuration)
    applyVisibility(preferredScreen: preferredScreen)
  }

  func refreshLayout(preferredScreen: NSScreen?) {
    guard enabled else { return }
    applyVisibility(preferredScreen: preferredScreen)
  }

  func hide() {
    hide(event: "hidden")
  }

  private func hide(event: String) {
    panel?.orderOut(nil)
    activeScreenNumber = nil
    writeDiagnostics(event: event)
  }

  private func applyVisibility(preferredScreen: NSScreen?) {
    guard enabled else {
      hide(event: "disabled-before-visibility")
      return
    }

    guard let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first else {
      hide(event: "no-screen")
      return
    }

    let configuration = state.configuration
    let rawSafeAreaTop = screen.safeAreaInsets.top
    let hasHardwareNotch = rawSafeAreaTop.isFinite && rawSafeAreaTop > 0
    guard configuration.showOnDisplaysWithoutNotch || hasHardwareNotch else {
      hide(event: "screen-without-notch")
      writeDiagnostics(event: "screen-without-notch", screen: screen)
      return
    }

    let screenGeometry = NotchHUDLayout.screenGeometry(for: screen)
    if hasHardwareNotch, screenGeometry.notch == nil {
      hide(event: "notch-geometry-unavailable")
      writeDiagnostics(event: "notch-geometry-unavailable", screen: screen)
      return
    }

    ensurePanel()
    guard let panel else {
      writeDiagnostics(event: "panel-allocation-failed", screen: screen)
      return
    }

    activeScreenNumber = screen.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")
    ] as? NSNumber

    let safeAreaTop = hasHardwareNotch ? screenGeometry.safeAreaTop : 0
    state.safeAreaTop = NotchHUDLayout.resolvedSafeAreaTop(safeAreaTop)
    state.notchWidth = screenGeometry.notch?.width ?? NotchHUDLayout.notchWidth

    let frame = NotchHUDLayout.panelFrame(
      for: screen.frame,
      safeAreaTop: safeAreaTop,
      configuration: configuration,
      notchGeometry: screenGeometry.notch)
    panel.setFrame(frame, display: true)
    panel.orderFrontRegardless()
    writeDiagnostics(event: "ordered", screen: screen, frame: frame)

    DispatchQueue.main.async { [weak self, weak screen] in
      self?.writeDiagnostics(event: "ordered-next-run-loop", screen: screen, frame: frame)
    }
  }

  private func ensurePanel() {
    guard panel == nil else { return }

    let indicatorPanel = Self.makePanel()
    indicatorPanel.contentViewController = NSHostingController(
      rootView: NotchHUDIndicatorView(state: state))
    panel = indicatorPanel
  }

  private func writeDiagnostics(
    event: String,
    screen: NSScreen? = nil,
    frame: NSRect? = nil
  ) {
    guard let path = ProcessInfo.processInfo.environment["MACVITALS_NOTCH_DIAGNOSTICS_PATH"],
      !path.isEmpty
    else {
      return
    }

    let configuration = NotchHUDConfigurationPolicy.normalized(state.configuration)
    let primaryReading = NotchHUDReadingResolver.resolve(
      snapshot: state.snapshot,
      metric: configuration.metric,
      warningThreshold: configuration.warningThreshold,
      criticalThreshold: configuration.criticalThreshold)
    let secondaryMetric = configuration.secondaryMetric ?? configuration.metric
    let secondaryDefaults = secondaryMetric.notchIndicatorDefaultThresholds
    let secondaryReading = NotchHUDReadingResolver.resolve(
      snapshot: state.snapshot,
      metric: secondaryMetric,
      warningThreshold: configuration.secondaryWarningThreshold ?? secondaryDefaults.warning,
      criticalThreshold: configuration.secondaryCriticalThreshold ?? secondaryDefaults.critical)
    let primarySegment = NotchHUDIndicatorSegments.primary(
      progress: primaryReading.progress,
      count: configuration.indicatorCount)
    let secondarySegment = NotchHUDIndicatorSegments.secondary(
      progress: secondaryReading.progress)

    var payload: [String: Any] = [
      "event": event,
      "enabled": enabled,
      "panelAllocated": panel != nil,
      "panelVisible": panel?.isVisible ?? false,
      "panelWindowNumber": panel?.windowNumber ?? 0,
      "screenCount": NSScreen.screens.count,
      "indicatorCount": configuration.indicatorCount.rawValue,
      "primaryMetric": configuration.metric.rawValue,
      "secondaryMetric": configuration.secondaryMetric?.rawValue ?? NSNull(),
      "showValueText": configuration.showValueText,
      "showSensorName": configuration.showSensorName,
      "primaryProgress": primaryReading.progress,
      "secondaryProgress": secondaryReading.progress,
      "primaryTrimStart": primarySegment.from,
      "primaryTrimEnd": primarySegment.to,
      "secondaryTrimStart": secondarySegment.from,
      "secondaryTrimEnd": secondarySegment.to,
      "resolvedNotchWidth": state.notchWidth,
    ]

    if let screen {
      let screenGeometry = NotchHUDLayout.screenGeometry(for: screen)
      payload["safeAreaTop"] = screen.safeAreaInsets.top
      payload["resolvedSafeAreaTop"] = screenGeometry.safeAreaTop
      payload["backingScaleFactor"] = screen.backingScaleFactor
      payload["screenX"] = screen.frame.minX
      payload["screenY"] = screen.frame.minY
      payload["screenWidth"] = screen.frame.width
      payload["screenHeight"] = screen.frame.height

      if let hardwareGeometry = screenGeometry.notch {
        payload["hardwareNotchCenterX"] = hardwareGeometry.centerX
        payload["hardwareNotchWidth"] = hardwareGeometry.width
      }
    }

    if let frame {
      payload["frameX"] = frame.minX
      payload["frameY"] = frame.minY
      payload["frameWidth"] = frame.width
      payload["frameHeight"] = frame.height

      let lineWidth = CGFloat(configuration.lineThickness)
      let contourGeometry = NotchHUDLayout.contourGeometry(
        in: frame.size,
        safeAreaTop: state.safeAreaTop,
        lineThickness: lineWidth,
        notchWidth: state.notchWidth)
      let cutoutRect = NotchHUDLayout.hardwareCutoutRect(
        in: frame.size,
        contourGeometry: contourGeometry,
        lineThickness: lineWidth)
      payload["contourShoulderRadius"] = contourGeometry.shoulderRadius
      payload["hardwareCutoutMaskX"] = cutoutRect.minX
      payload["hardwareCutoutMaskY"] = cutoutRect.minY
      payload["hardwareCutoutMaskWidth"] = cutoutRect.width
      payload["hardwareCutoutMaskHeight"] = cutoutRect.height
    }

    guard let data = try? JSONSerialization.data(
      withJSONObject: payload,
      options: [.prettyPrinted, .sortedKeys])
    else {
      return
    }
    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
  }

  private static func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .stationary,
    ]
    panel.animationBehavior = .utilityWindow
    panel.ignoresMouseEvents = true
    panel.isMovable = false
    panel.isMovableByWindowBackground = false
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    return panel
  }
}
