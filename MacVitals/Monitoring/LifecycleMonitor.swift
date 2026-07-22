import AppKit
import Foundation

@MainActor
final class LifecycleMonitor {
  static let shared = LifecycleMonitor(center: NSWorkspace.shared.notificationCenter)

  private let center: NotificationCenter
  private var observers: [NSObjectProtocol] = []

  var isStarted: Bool { !observers.isEmpty }
  var observerCount: Int { observers.count }

  init(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
    self.center = center
  }

  func start(coordinator: MetricsCoordinator) {
    guard !isStarted else { return }

    observers.append(
      center.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil,
        queue: .main
      ) { _ in
        Task { @MainActor in coordinator.handleSleep() }
      })
    observers.append(
      center.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
      ) { _ in
        Task { @MainActor in coordinator.handleWake() }
      })
  }

  func stop() {
    observers.forEach(center.removeObserver)
    observers.removeAll(keepingCapacity: false)
  }

  deinit {
    observers.forEach(center.removeObserver)
  }
}