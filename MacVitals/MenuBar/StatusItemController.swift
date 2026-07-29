import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private var cancellables: Set<AnyCancellable> = []
  private let coordinator: MetricsCoordinator
  private let settings: SettingsStore
  private let fanControl: FanControlClient

  init(
    coordinator: MetricsCoordinator,
    settings: SettingsStore,
    fanControl: FanControlClient
  ) {
    self.coordinator = coordinator
    self.settings = settings
    self.fanControl = fanControl
    super.init()

    let root = ThemedOverviewRoot {
      OverviewView()
        .environmentObject(coordinator)
        .environmentObject(settings)
        .environmentObject(fanControl)
    }
    popover.contentViewController = NSHostingController(rootView: root)
    popover.behavior = .transient
    popover.contentSize = NSSize(
      width: OverviewLayout.width,
      height: OverviewLayout.height)

    if let button = statusItem.button {
      button.target = self
      button.action = #selector(togglePopover)
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      button.toolTip = "MacVitals"
      button.image = nil
      button.imagePosition = .noImage
      button.imageHugsTitle = true
    }

    coordinator.$snapshot.combineLatest(settings.$enabledMetrics)
      .receive(on: RunLoop.main)
      .sink { [weak self] snapshot, metrics in
        self?.render(snapshot: snapshot, metrics: metrics)
      }
      .store(in: &cancellables)
  }

  @objc private func togglePopover() {
    guard let button = statusItem.button else { return }
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu()
      return
    }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      showPopover(relativeTo: button)
    }
  }

  private func showContextMenu() {
    let menu = NSMenu()
    menu.addItem(
      withTitle: NSLocalizedString("Open MacVitals", comment: ""),
      action: #selector(openPopover), keyEquivalent: "")
    menu.addItem(
      withTitle: NSLocalizedString("Preferences…", comment: ""),
      action: #selector(openPreferences), keyEquivalent: ",")
    menu.addItem(.separator())
    menu.addItem(
      withTitle: NSLocalizedString("Quit MacVitals", comment: ""),
      action: #selector(quit), keyEquivalent: "q")
    for item in menu.items { item.target = self }
    statusItem.menu = menu
    statusItem.button?.performClick(nil)
    statusItem.menu = nil
  }

  @objc private func openPopover() {
    guard let button = statusItem.button else { return }
    statusItem.menu = nil
    showPopover(relativeTo: button)
  }

  private func showPopover(relativeTo button: NSStatusBarButton) {
    guard !popover.isShown else { return }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openPreferences() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func render(snapshot: SystemSnapshot, metrics: [MenuMetric]) {
    let normalized = MenuLayoutRules.normalized(metrics)

    if let button = statusItem.button {
      let appearance = button.effectiveAppearance
      let foregroundColor = MenuBarStatusTitleRenderer.statusBarForegroundColor(
        for: appearance)

      button.image = nil
      button.imagePosition = .noImage
      button.contentTintColor = foregroundColor
      button.attributedTitle = MenuBarStatusTitleRenderer.attributedTitle(
        snapshot: snapshot,
        metrics: normalized,
        appearance: appearance)
      button.setAccessibilityLabel("MacVitals")
      button.setAccessibilityValue(
        MenuBarRenderer.render(snapshot: snapshot, metrics: normalized))
    }
    statusItem.length = NSStatusItem.variableLength
  }
}
