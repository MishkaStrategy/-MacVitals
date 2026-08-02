import AppKit
import SwiftUI

@MainActor
final class NotchHUDController {
  static let defaultsKey = "experimentalNotchHUDEnabled"

  private let state = NotchHUDState()
  private var railPanel: NSPanel?
  private var detailPanel: NSPanel?
  private var activeScreenNumber: NSNumber?

  var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: Self.defaultsKey)
  }

  var hasAllocatedPanelsForTesting: Bool {
    railPanel != nil || detailPanel != nil
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
    guard isEnabled else {
      hide()
      return
    }

    state.snapshot = snapshot
    applyVisibility(preferredScreen: preferredScreen)
  }

  func hide() {
    railPanel?.orderOut(nil)
    detailPanel?.orderOut(nil)
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

    ensurePanels()
    guard let railPanel, let detailPanel else { return }

    let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
      as? NSNumber
    activeScreenNumber = screenNumber
    layout(railPanel: railPanel, detailPanel: detailPanel, on: screen)

    railPanel.orderFrontRegardless()
    detailPanel.orderFrontRegardless()
  }

  private func ensurePanels() {
    guard railPanel == nil, detailPanel == nil else { return }

    let rail = Self.makePanel()
    let detail = Self.makePanel()
    rail.contentViewController = NSHostingController(
      rootView: NotchHUDRailView(state: state))
    detail.contentViewController = NSHostingController(
      rootView: NotchHUDDetailView(state: state))
    railPanel = rail
    detailPanel = detail
  }

  private func layout(
    railPanel: NSPanel,
    detailPanel: NSPanel,
    on screen: NSScreen
  ) {
    let railFrame = NotchHUDLayout.railFrame(
      for: screen.frame,
      safeAreaTop: screen.safeAreaInsets.top)
    let detailFrame = NotchHUDLayout.detailFrame(
      below: railFrame,
      screenFrame: screen.frame)

    railPanel.setFrame(railFrame, display: true)
    detailPanel.setFrame(detailFrame, display: true)
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
