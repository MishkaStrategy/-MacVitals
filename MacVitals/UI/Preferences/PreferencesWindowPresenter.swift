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

    let rootView = ThemedPreferencesRootView()
      .environmentObject(coordinator)
      .environmentObject(settings)
      .environmentObject(fanControl)
      .frame(minWidth: 860, minHeight: 700)

    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = L10n.string("Preferences")
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.toolbarStyle = .unifiedCompact
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.setContentSize(NSSize(width: 920, height: 760))
    window.minSize = NSSize(width: 860, height: 700)
    window.isReleasedWhenClosed = false
    window.center()

    let controller = NSWindowController(window: window)
    windowController = controller
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
