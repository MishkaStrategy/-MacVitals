import AppKit
import Foundation

@MainActor
final class LifecycleMonitor {
    static let shared = LifecycleMonitor()
    private var observers: [NSObjectProtocol] = []

    func start(coordinator: MetricsCoordinator) {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in coordinator.handleSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in coordinator.handleWake() }
        })
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }
}
