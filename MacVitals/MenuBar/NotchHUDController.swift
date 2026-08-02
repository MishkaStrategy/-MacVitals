import AppKit
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

    guard enabled else {
      hide()
      return
    }

    state.snapshot = snapshot
    state.configuration = NotchHUDConfigurationPolicy.normalized(configuration)
    applyVisibility(preferredScreen: preferredScreen)
  }

  func hide() {
    panel?.orderOut(nil)
    activeScreenNumber = nil
  }

  private func applyVisibility(preferredScreen: NSScreen?) {
    guard enabled else {
      hide()
      return
    }

    guard let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first else {
      hide()
      return
    }

    let configuration = state.configuration
    let safeAreaTop = screen.safeAreaInsets.top
    guard configuration.showOnDisplaysWithoutNotch || safeAreaTop > 0 else {
      hide()
      return
    }

    ensurePanel()
    guard let panel else { return }

    activeScreenNumber = screen.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")
    ] as? NSNumber
    state.safeAreaTop = NotchHUDLayout.resolvedSafeAreaTop(safeAreaTop)

    let frame = NotchHUDLayout.panelFrame(
      for: screen.frame,
      safeAreaTop: safeAreaTop,
      configuration: configuration)
    panel.setFrame(frame, display: true)
    panel.orderFrontRegardless()
  }

  private func ensurePanel() {
    guard panel == nil else { return }

    let indicatorPanel = Self.makePanel()
    indicatorPanel.contentViewController = NSHostingController(
      rootView: NotchHUDIndicatorView(state: state))
    panel = indicatorPanel
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
