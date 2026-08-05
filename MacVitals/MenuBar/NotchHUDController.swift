import AppKit
import Foundation
import SwiftUI

nonisolated struct NotchHUDRenderOutput: Equatable, Sendable {
  let primary: NotchHUDReading
  let secondary: NotchHUDReading?
}

nonisolated enum NotchHUDRenderOutputResolver {
  static func resolve(
    snapshot: SystemSnapshot,
    configuration: NotchHUDConfiguration
  ) -> NotchHUDRenderOutput {
    let normalized = NotchHUDConfigurationPolicy.normalized(configuration)
    let primary = NotchHUDReadingResolver.resolve(
      snapshot: snapshot,
      metric: normalized.metric,
      warningThreshold: normalized.warningThreshold,
      criticalThreshold: normalized.criticalThreshold)

    let secondary = normalized.secondaryMetric.map { metric in
      let defaults = metric.notchIndicatorDefaultThresholds
      return NotchHUDReadingResolver.resolve(
        snapshot: snapshot,
        metric: metric,
        warningThreshold: normalized.secondaryWarningThreshold ?? defaults.warning,
        criticalThreshold: normalized.secondaryCriticalThreshold ?? defaults.critical)
    }
    return NotchHUDRenderOutput(primary: primary, secondary: secondary)
  }
}

@MainActor
final class NotchHUDController {
  nonisolated static let defaultsKey = "experimentalNotchHUDEnabled"

  private let state = NotchHUDState()
  private let diagnosticsURL: URL? = {
    guard let path = ProcessInfo.processInfo.environment["MACVITALS_NOTCH_DIAGNOSTICS_PATH"],
      !path.isEmpty
    else { return nil }
    return URL(fileURLWithPath: path)
  }()
  private var panel: NSPanel?
  private var enabled = false
  private var activeScreenNumber: NSNumber?
  private var lastPanelFrame: NSRect?
  private var lastRenderOutput: NotchHUDRenderOutput?

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

    let normalizedConfiguration = NotchHUDConfigurationPolicy.normalized(configuration)
    let configurationChanged = state.configuration != normalizedConfiguration
    if configurationChanged {
      state.configuration = normalizedConfiguration
    }

    let renderOutput = NotchHUDRenderOutputResolver.resolve(
      snapshot: snapshot,
      configuration: normalizedConfiguration)
    if configurationChanged || renderOutput != lastRenderOutput {
      state.snapshot = snapshot
      lastRenderOutput = renderOutput
    }
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
    let safeAreaTop = screen.safeAreaInsets.top
    guard configuration.showOnDisplaysWithoutNotch || safeAreaTop > 0 else {
      hide(event: "screen-without-notch")
      writeDiagnostics(event: "screen-without-notch", screen: screen)
      return
    }

    ensurePanel()
    guard let panel else {
      writeDiagnostics(event: "panel-allocation-failed", screen: screen)
      return
    }

    let screenNumber = screen.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")
    ] as? NSNumber
    let screenChanged = activeScreenNumber != screenNumber
    activeScreenNumber = screenNumber

    let hardwareGeometry = NotchHUDLayout.hardwareNotchGeometry(
      screenFrame: screen.frame,
      safeAreaTop: safeAreaTop,
      auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
      auxiliaryTopRightArea: screen.auxiliaryTopRightArea)

    let resolvedSafeAreaTop = NotchHUDLayout.resolvedSafeAreaTop(safeAreaTop)
    if state.safeAreaTop != resolvedSafeAreaTop {
      state.safeAreaTop = resolvedSafeAreaTop
    }

    let resolvedNotchWidth = hardwareGeometry?.width ?? NotchHUDLayout.notchWidth
    if state.notchWidth != resolvedNotchWidth {
      state.notchWidth = resolvedNotchWidth
    }

    let frame = NotchHUDLayout.panelFrame(
      for: screen.frame,
      safeAreaTop: safeAreaTop,
      configuration: configuration,
      notchGeometry: hardwareGeometry)

    if lastPanelFrame != frame {
      panel.setFrame(frame, display: true)
      lastPanelFrame = frame
    }

    if !panel.isVisible || screenChanged {
      panel.orderFrontRegardless()
      writeDiagnostics(event: "ordered", screen: screen, frame: frame)

      DispatchQueue.main.async { [weak self, weak screen] in
        self?.writeDiagnostics(event: "ordered-next-run-loop", screen: screen, frame: frame)
      }
    } else {
      writeDiagnostics(event: "updated", screen: screen, frame: frame)
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
    guard let diagnosticsURL else { return }

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
      payload["safeAreaTop"] = screen.safeAreaInsets.top
      payload["screenX"] = screen.frame.minX
      payload["screenY"] = screen.frame.minY
      payload["screenWidth"] = screen.frame.width
      payload["screenHeight"] = screen.frame.height

      if let hardwareGeometry = NotchHUDLayout.hardwareNotchGeometry(
        screenFrame: screen.frame,
        safeAreaTop: screen.safeAreaInsets.top,
        auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
        auxiliaryTopRightArea: screen.auxiliaryTopRightArea)
      {
        payload["hardwareNotchCenterX"] = hardwareGeometry.centerX
        payload["hardwareNotchWidth"] = hardwareGeometry.width
      }
    }

    if let frame {
      payload["frameX"] = frame.minX
      payload["frameY"] = frame.minY
      payload["frameWidth"] = frame.width
      payload["frameHeight"] = frame.height
    }

    guard let data = try? JSONSerialization.data(
      withJSONObject: payload,
      options: [.prettyPrinted, .sortedKeys])
    else {
      return
    }
    try? data.write(to: diagnosticsURL, options: .atomic)
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
