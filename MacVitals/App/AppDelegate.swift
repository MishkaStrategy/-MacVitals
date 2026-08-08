import AppKit
import Combine
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings = SettingsStore()
  let coordinator = MetricsCoordinator()
  let fanControl = FanControlClient()
  private let notificationCoordinator = NotificationCoordinator()
  private let consumptionHistory = HistoricalConsumptionCenter.shared
  private let autonomousHistoryEnabled = AutonomousSamplingPolicy.isEnabled
  private let historyTermination = HistoricalConsumptionTerminationCoordinator()
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

    if autonomousHistoryEnabled {
      settings.$samplingInterval
        .removeDuplicates()
        .dropFirst()
        .sink { [weak self] interval in
          self?.consumptionHistory.restart(interval: interval)
        }
        .store(in: &cancellables)
    }

    coordinator.onSnapshot = { [weak self] snapshot in
      self?.notificationCoordinator.process(snapshot: snapshot)
    }

    fanControl.refreshStatus()
    coordinator.start()
    if autonomousHistoryEnabled {
      consumptionHistory.start(interval: settings.samplingInterval)
    }
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

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard autonomousHistoryEnabled else { return .terminateNow }

    historyTermination.begin(
      flush: { [weak self] in
        await self?.consumptionHistory.stopAndFlush()
      },
      completion: { [weak sender] outcome in
        if outcome == .timedOut {
          Logger.lifecycle.warning("Historical consumption final flush timed out; terminating")
        }
        sender?.reply(toApplicationShouldTerminate: true)
      })
    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
    historyTermination.cancel()
    fanControl.setAllAutomatic()
    fanControl.invalidateConnection()
    consumptionHistory.stop(flush: false)
    coordinator.stop()
    coordinator.onSnapshot = nil
    notificationCoordinator.onAuthorizationStateChange = nil
    LifecycleMonitor.shared.stop()
    cancellables.removeAll()
    Logger.lifecycle.info("MacVitals stopped")
  }
}
