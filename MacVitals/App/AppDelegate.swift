import AppKit
import Combine
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings = SettingsStore()
  let coordinator = MetricsCoordinator()
  let fanControl = FanControlClient()
  private let notificationCoordinator = NotificationCoordinator()
  private let terminationGate = ApplicationTerminationGate()
  private var statusController: StatusItemController?
  private var cancellables = Set<AnyCancellable>()
  private var terminationTimeoutTask: Task<Void, Never>?
  private weak var pendingTerminationApplication: NSApplication?

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

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard FanTerminationPolicy.shouldDelayTermination(for: fanControl.state) else {
      return .terminateNow
    }
    guard terminationGate.begin() else { return .terminateLater }

    pendingTerminationApplication = sender
    terminationTimeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(
          nanoseconds: FanTerminationPolicy.restoreTimeoutNanoseconds)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self?.finishPendingTermination()
    }

    fanControl.restoreAllAutomaticForTermination { [weak self] _ in
      self?.finishPendingTermination()
    }
    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) {
    terminationTimeoutTask?.cancel()
    terminationTimeoutTask = nil
    pendingTerminationApplication = nil
    terminationGate.cancel()
    fanControl.invalidateConnection()
    coordinator.stop()
    coordinator.onSnapshot = nil
    notificationCoordinator.onAuthorizationStateChange = nil
    LifecycleMonitor.shared.stop()
    cancellables.removeAll()
    Logger.lifecycle.info("MacVitals stopped")
  }

  private func finishPendingTermination() {
    terminationGate.complete { [self] in
      terminationTimeoutTask?.cancel()
      terminationTimeoutTask = nil
      let application = pendingTerminationApplication
      pendingTerminationApplication = nil
      application?.reply(toApplicationShouldTerminate: true)
    }
  }
}
