import AppKit
import SwiftUI

@MainActor
final class NotchHUDController {
  static let defaultsKey = "experimentalNotchHUDEnabled"

  private let state: NotchHUDState
  private let railPanel: NSPanel
  private let detailPanel: NSPanel
  private var activeScreenNumber: NSNumber?

  init() {
    let state = NotchHUDState()
    self.state = state

    railPanel = Self.makePanel(ignoresMouseEvents: true)
    detailPanel = Self.makePanel(ignoresMouseEvents: true)

    railPanel.contentViewController = NSHostingController(
      rootView: NotchHUDRailView(state: state))
    detailPanel.contentViewController = NSHostingController(
      rootView: NotchHUDDetailView(state: state))
  }

  var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: Self.defaultsKey)
  }

  func toggle(preferredScreen: NSScreen?) {
    let nextValue = !isEnabled
    UserDefaults.standard.set(nextValue, forKey: Self.defaultsKey)
    applyVisibility(preferredScreen: preferredScreen)
  }

  func update(
    snapshot: SystemSnapshot,
    preferredScreen: NSScreen?
  ) {
    state.snapshot = snapshot
    applyVisibility(preferredScreen: preferredScreen)
  }

  func hide() {
    railPanel.orderOut(nil)
    detailPanel.orderOut(nil)
    activeScreenNumber = nil
  }

  private func applyVisibility(preferredScreen: NSScreen?) {
    guard isEnabled else {
      hide()
      return
    }

    guard let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first else {
      hide()
      return
    }

    let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
      as? NSNumber
    if activeScreenNumber != screenNumber || !railPanel.isVisible || !detailPanel.isVisible {
      activeScreenNumber = screenNumber
      layout(on: screen)
    } else {
      layout(on: screen)
    }

    railPanel.orderFrontRegardless()
    detailPanel.orderFrontRegardless()
  }

  private func layout(on screen: NSScreen) {
    let railFrame = NotchHUDLayout.railFrame(
      for: screen.frame,
      safeAreaTop: screen.safeAreaInsets.top)
    let detailFrame = NotchHUDLayout.detailFrame(
      below: railFrame,
      screenFrame: screen.frame)

    railPanel.setFrame(railFrame, display: true)
    detailPanel.setFrame(detailFrame, display: true)
  }

  private static func makePanel(ignoresMouseEvents: Bool) -> NSPanel {
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
    panel.ignoresMouseEvents = ignoresMouseEvents
    panel.isMovable = false
    panel.isMovableByWindowBackground = false
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    return panel
  }
}
