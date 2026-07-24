import AppKit
import Foundation

@MainActor
protocol LifecycleCoordinating: AnyObject, Sendable {
  func handleSleep()
  func handleWake()
}

extension MetricsCoordinator: LifecycleCoordinating {}

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

  func start(coordinator: any LifecycleCoordinating) {
    guard !isStarted else { return }

    observers.append(
      center.addObserver(
        forName: NSWorkspace.willSleepNotification,
        object: nil,
        queue: .main
      ) { [weak coordinator] _ in
        MainActor.assumeIsolated {
          coordinator?.handleSleep()
        }
      })
    observers.append(
      center.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: .main
      ) { [weak coordinator] _ in
        MainActor.assumeIsolated {
          coordinator?.handleWake()
        }
      })
  }

  func stop() {
    observers.forEach(center.removeObserver)
    observers.removeAll(keepingCapacity: false)
  }
}
