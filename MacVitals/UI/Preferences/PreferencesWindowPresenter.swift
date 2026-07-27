import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowPresenter {
  static let shared = PreferencesWindowPresenter()

  private var windowController: NSWindowController?

  func show(
    coordinator: MetricsCoordinator,
    settings: SettingsStore,
    fanControl: FanControlClient
  ) {
    if let window = windowController?.window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let rootView = PreferencesView()
      .environmentObject(coordinator)
      .environmentObject(settings)
      .environmentObject(fanControl)
      .frame(minWidth: 620, minHeight: 520)

    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = L10n.string("Preferences")
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.setContentSize(NSSize(width: 680, height: 580))
    window.minSize = NSSize(width: 620, height: 520)
    window.isReleasedWhenClosed = false
    window.center()

    let controller = NSWindowController(window: window)
    windowController = controller
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
