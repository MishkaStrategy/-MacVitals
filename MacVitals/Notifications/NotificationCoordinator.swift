import Foundation
import UserNotifications

nonisolated enum NotificationAuthorizationState: Equatable, Sendable {
  case unknown
  case notDetermined
  case denied
  case authorized
  case provisional
  case failed(String)

  var canDeliver: Bool {
    switch self {
    case .authorized, .provisional: return true
    default: return false
    }
  }

  var message: String? {
    switch self {
    case .unknown:
      return "Checking notification permission…"
    case .notDetermined:
      return "macOS will ask for notification permission when alerts are enabled."
    case .denied:
      return "Notifications are disabled in System Settings › Notifications › MacVitals."
    case .authorized:
      return nil
    case .provisional:
      return "Notifications are authorized for quiet delivery."
    case .failed(let message):
      return message
    }
  }
}

nonisolated enum NotificationAuthorizationMapper {
  static func state(for status: UNAuthorizationStatus) -> NotificationAuthorizationState {
    switch status {
    case .notDetermined: return .notDetermined
    case .denied: return .denied
    case .authorized: return .authorized
    case .provisional: return .provisional
    @unknown default: return .unknown
    }
  }
}

@MainActor
final class NotificationCoordinator {
  var onAuthorizationStateChange: ((NotificationAuthorizationState) -> Void)?

  private(set) var authorizationState: NotificationAuthorizationState = .unknown {
    didSet {
      guard authorizationState != oldValue else { return }
      onAuthorizationStateChange?(authorizationState)
    }
  }

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

    Task { [weak self] in
      guard let self else { return }
      await refreshAuthorizationState()
      guard enabled, authorizationState == .notDetermined else { return }

      do {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        await refreshAuthorizationState()
      } catch {
        authorizationState = .failed(
          "Could not request notification permission: \(error.localizedDescription)")
      }
    }
  }

  func refreshAuthorizationState() async {
    let settings = await center.notificationSettings()
    authorizationState = NotificationAuthorizationMapper.state(for: settings.authorizationStatus)
  }

  func process(
    snapshot: SystemSnapshot,
    memoryThreshold: Double,
    lowBatteryThreshold: Double
  ) {
    guard enabled, authorizationState.canDeliver else { return }

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

      Task { [weak self] in
        guard let self else { return }
        do {
          try await center.add(request)
        } catch {
          authorizationState = .failed(
            "Could not deliver a notification: \(error.localizedDescription)")
        }
      }
    }
  }
}
