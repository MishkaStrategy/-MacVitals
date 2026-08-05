import AppKit
import Combine
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings = SettingsStore()
  let coordinator = MetricsCoordinator()
  let fanControl = FanControlClient()
  private let notificationCoordinator = NotificationCoordinator()
  private var statusController: StatusItemController?
  private var cancellables = Set<AnyCancellable>()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
    statusController = StatusItemController(
      coordinator: coordinator,
      settings: settings,
      fanControl: fanControl)

    notificationCoordinator.onAuthorizationStateChange = { [weak self] state in
      self?.settings.setNotificationAuthorizationState(state)
    }

    settings.$notificationsEnabled
      .combineLatest(
        settings.$memoryAlertsEnabled.combineLatest(settings.$memoryAlertThreshold),
        settings.$lowBatteryAlertsEnabled.combineLatest(settings.$lowBatteryAlertThreshold)
      )
      .sink { [weak self] enabled, memoryRule, batteryRule in
        self?.notificationCoordinator.setEnabled(
          enabled,
          memoryAlertsEnabled: memoryRule.0,
          memoryThreshold: memoryRule.1,
          lowBatteryAlertsEnabled: batteryRule.0,
          lowBatteryThreshold: batteryRule.1)
      }
      .store(in: &cancellables)

    coordinator.onSnapshot = { [weak self] snapshot in
      self?.notificationCoordinator.process(snapshot: snapshot)
    }

    fanControl.refreshStatus()
    coordinator.start()
    LifecycleMonitor.shared.start(coordinator: coordinator)
    Logger.lifecycle.info("MacVitals started")
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    settings.refreshLaunchAtLoginState()
    fanControl.refreshStatus()
    Task { [weak self] in
      await self?.notificationCoordinator.refreshAuthorizationState()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Termination must never start helper registration or open System Settings.
    // Restore automatic control only when an already-approved helper is ready.
    if fanControl.state.canControl {
      fanControl.setAllAutomatic()
    }
    fanControl.invalidateConnection()
    coordinator.stop()
    coordinator.onSnapshot = nil
    notificationCoordinator.onAuthorizationStateChange = nil
    LifecycleMonitor.shared.stop()
    cancellables.removeAll()
    Logger.lifecycle.info("MacVitals stopped")
  }
}
