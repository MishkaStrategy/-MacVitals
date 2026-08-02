import AppKit
import SwiftUI

@MainActor
final class NotchHUDController {
  static let defaultsKey = "experimentalNotchHUDEnabled"

  private let state = NotchHUDState()
  private var leftPanel: NSPanel?
  private var rightPanel: NSPanel?
  private var enabled = false
  private var activeScreenNumber: NSNumber?

  var isEnabled: Bool { enabled }

  var hasAllocatedPanelsForTesting: Bool {
    leftPanel != nil || rightPanel != nil
  }

  func update(
    snapshot: SystemSnapshot,
    preferredScreen: NSScreen?,
    enabled: Bool
  ) {
    self.enabled = enabled

    guard enabled else {
      hide()
      return
    }

    state.snapshot = snapshot
    applyVisibility(preferredScreen: preferredScreen)
  }

  func hide() {
    leftPanel?.orderOut(nil)
    rightPanel?.orderOut(nil)
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

    ensurePanels()
    guard let leftPanel, let rightPanel else { return }

    activeScreenNumber = screen.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")
    ] as? NSNumber

    let frames = NotchHUDLayout.sideFrames(
      for: screen.frame,
      safeAreaTop: screen.safeAreaInsets.top)
    leftPanel.setFrame(frames.left, display: true)
    rightPanel.setFrame(frames.right, display: true)

    leftPanel.orderFrontRegardless()
    rightPanel.orderFrontRegardless()
  }

  private func ensurePanels() {
    guard leftPanel == nil, rightPanel == nil else { return }

    let left = Self.makePanel()
    let right = Self.makePanel()
    left.contentViewController = NSHostingController(
      rootView: NotchHUDSideView(state: state, side: .left))
    right.contentViewController = NSHostingController(
      rootView: NotchHUDSideView(state: state, side: .right))
    leftPanel = left
    rightPanel = right
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
