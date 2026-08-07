import AppKit
import SwiftUI

@MainActor
final class SupplementalMetricTabbedWindowPresenter: NSObject, NSWindowDelegate {
  static let shared = SupplementalMetricTabbedWindowPresenter()

  private var windowController: NSWindowController?

  func show(
    kind: SupplementalMetricDetailKind,
    settings: SettingsStore,
    networkMonitor: NetworkTrafficMonitor,
    storageMonitor: StorageUsageMonitor
  ) {
    let rootView = ThemedMetricDetailRoot(metric: kind.themeMetricKind) {
      SupplementalMetricDetailView(
        kind: kind,
        networkMonitor: networkMonitor,
        storageMonitor: storageMonitor)
        .environmentObject(settings)
    }

    let hostingController = NSHostingController(rootView: rootView)
    let size = preferredSize(for: kind)

    if let window = windowController?.window {
      window.contentViewController = hostingController
      window.title = kind.title
      window.setContentSize(size)
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let window = NSWindow(contentViewController: hostingController)
    window.title = kind.title
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.setContentSize(size)
    window.minSize = NSSize(width: 620, height: 500)
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.delegate = self
    window.center()

    let controller = NSWindowController(window: window)
    windowController = controller
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    windowController = nil
  }

  private func preferredSize(for kind: SupplementalMetricDetailKind) -> NSSize {
    switch kind {
    case .network: return NSSize(width: 720, height: 650)
    case .storage: return NSSize(width: 720, height: 610)
    }
  }
}
