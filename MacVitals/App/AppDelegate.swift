import AppKit
import Combine
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings = SettingsStore()
  let coordinator = MetricsCoordinator()
  private let notificationCoordinator = NotificationCoordinator()
  private var statusController: StatusItemController?
  private var cancellables = Set<AnyCancellable>()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
    statusController = StatusItemController(coordinator: coordinator, settings: settings)

    settings.$notificationsEnabled
      .combineLatest(settings.$memoryAlertThreshold, settings.$lowBatteryAlertThreshold)
      .sink { [weak self] enabled, memoryThreshold, batteryThreshold in
        self?.notificationCoordinator.setEnabled(
          enabled,
          memoryThreshold: memoryThreshold,
          lowBatteryThreshold: batteryThreshold)
      }
      .store(in: &cancellables)

    coordinator.onSnapshot = { [weak self] snapshot in
      guard let self else { return }
      notificationCoordinator.process(
        snapshot: snapshot,
        memoryThreshold: settings.memoryAlertThreshold,
        lowBatteryThreshold: settings.lowBatteryAlertThreshold)
    }

    coordinator.start()
    LifecycleMonitor.shared.start(coordinator: coordinator)
    Logger.lifecycle.info("MacVitals started")
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    settings.refreshLaunchAtLoginState()
  }

  func applicationWillTerminate(_ notification: Notification) {
    coordinator.stop()
    coordinator.onSnapshot = nil
    LifecycleMonitor.shared.stop()
    cancellables.removeAll()
    Logger.lifecycle.info("MacVitals stopped")
  }
}
