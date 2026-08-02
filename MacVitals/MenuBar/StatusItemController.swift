import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let popover = NSPopover()
  private let notchHUD = NotchHUDController()
  private let caffeinate = CaffeinateController()
  private var hudSettingsWindowController: NotchHUDSettingsWindowController?
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
        .environmentObject(caffeinate)
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
      button.title = ""
      button.attributedTitle = NSAttributedString(string: "")
      button.imagePosition = .imageOnly
      button.imageScaling = .scaleNone
      button.imageHugsTitle = true
      button.contentTintColor = nil
      button.setAccessibilityIdentifier("macVitalsStatusItem")
    }

    Publishers.CombineLatest4(
      coordinator.$snapshot,
      settings.$enabledMetrics,
      settings.$showAroundStatusBar,
      settings.$notchHUDConfiguration)
      .receive(on: RunLoop.main)
      .sink { [weak self] snapshot, metrics, showAroundStatusBar, configuration in
        self?.render(
          snapshot: snapshot,
          metrics: metrics,
          showAroundStatusBar: showAroundStatusBar,
          notchHUDConfiguration: configuration)
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

    menu.addItem(
      withTitle: L10n.string(
        settings.showAroundStatusBar ? "Hide around status bar" : "Show around status bar"),
      action: #selector(toggleNotchHUD), keyEquivalent: "")
    menu.addItem(
      withTitle: L10n.string("HUD Settings…"),
      action: #selector(openNotchHUDSettings), keyEquivalent: "")

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

  @objc private func toggleNotchHUD() {
    settings.showAroundStatusBar.toggle()
    notchHUD.update(
      snapshot: coordinator.snapshot,
      preferredScreen: statusItem.button?.window?.screen,
      enabled: settings.showAroundStatusBar,
      configuration: settings.notchHUDConfiguration)
  }

  @objc private func openNotchHUDSettings() {
    let controller: NotchHUDSettingsWindowController
    if let existing = hudSettingsWindowController {
      controller = existing
    } else {
      controller = NotchHUDSettingsWindowController(
        coordinator: coordinator,
        settings: settings)
      hudSettingsWindowController = controller
    }
    controller.present()
  }

  @objc private func openPreferences() {
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func quit() {
    caffeinate.stop()
    notchHUD.hide()
    NSApp.terminate(nil)
  }

  private func render(
    snapshot: SystemSnapshot,
    metrics: [MenuMetric],
    showAroundStatusBar: Bool,
    notchHUDConfiguration: NotchHUDConfiguration
  ) {
    let normalized = MenuLayoutRules.normalized(metrics)

    if let button = statusItem.button {
      button.title = ""
      button.attributedTitle = NSAttributedString(string: "")
      button.imagePosition = .imageOnly
      button.imageScaling = .scaleNone
      button.contentTintColor = nil
      button.image = MenuBarStatusTitleRenderer.lightImage(
        snapshot: snapshot,
        metrics: normalized)
      button.setAccessibilityLabel("MacVitals")
      button.setAccessibilityValue(
        MenuBarRenderer.render(snapshot: snapshot, metrics: normalized))

      notchHUD.update(
        snapshot: snapshot,
        preferredScreen: button.window?.screen,
        enabled: showAroundStatusBar,
        configuration: notchHUDConfiguration)
    }
    statusItem.length = NSStatusItem.variableLength
  }
}
