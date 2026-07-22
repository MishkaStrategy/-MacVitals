import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let coordinator = MetricsCoordinator()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        statusController = StatusItemController(coordinator: coordinator, settings: settings)
        coordinator.start()
        LifecycleMonitor.shared.start(coordinator: coordinator)
        Logger.lifecycle.info("MacVitals started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        LifecycleMonitor.shared.stop()
        Logger.lifecycle.info("MacVitals stopped")
    }
}
