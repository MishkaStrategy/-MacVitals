import Foundation
import UserNotifications

@MainActor
final class NotificationCoordinator {
  private var enabled = false
  private var policy = AlertPolicy()
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func setEnabled(
    _ enabled: Bool,
    memoryThreshold: Double,
    lowBatteryThreshold: Double
  ) {
    self.enabled = enabled
    policy = AlertPolicy(
      configuration: .init(
        memoryThresholdPercent: memoryThreshold,
        lowBatteryThresholdPercent: lowBatteryThreshold))

    guard enabled else { return }
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  func process(
    snapshot: SystemSnapshot,
    memoryThreshold: Double,
    lowBatteryThreshold: Double
  ) {
    guard enabled else { return }

    let events = policy.evaluate(snapshot: snapshot)
    for event in events {
      let content = UNMutableNotificationContent()
      content.title = event.title
      content.body = event.message
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: "macvitals.\(event.kind.rawValue).\(UUID().uuidString)",
        content: content,
        trigger: nil)
      center.add(request)
    }
  }
}
