import AppKit
import SwiftUI

@MainActor
final class MetricDetailWindowPresenter: NSObject, NSWindowDelegate {
  static let shared = MetricDetailWindowPresenter()

  private var windowController: NSWindowController?

  func show(
    kind: MetricDetailKind,
    coordinator: MetricsCoordinator,
    settings: SettingsStore,
    fanControl: FanControlClient
  ) {
    let rootView = ThemedOverviewRoot {
      MetricDetailView(kind: kind)
        .environmentObject(coordinator)
        .environmentObject(settings)
        .environmentObject(fanControl)
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

  func close() {
    windowController?.close()
  }

  func windowWillClose(_ notification: Notification) {
    windowController = nil
  }

  private func preferredSize(for kind: MetricDetailKind) -> NSSize {
    switch kind {
    case .fans: return NSSize(width: 660, height: 690)
    case .temperature: return NSSize(width: 660, height: 700)
    case .power: return NSSize(width: 660, height: 560)
    case .battery: return NSSize(width: 720, height: 820)
    case .cpu, .memory, .gpu: return NSSize(width: 720, height: 650)
    }
  }
}
