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

    guard enabled else {
      authorizationState = .unknown
      return
    }

    Task { [weak self] in
      guard let self else { return }
      await refreshAuthorizationState()
      guard authorizationState == .notDetermined else { return }

      do {
        try await requestAuthorization()
        await refreshAuthorizationState()
      } catch {
        authorizationState = .failed(
          "Could not request notification permission: \(error.localizedDescription)")
      }
    }
  }

  func refreshAuthorizationState() async {
    guard enabled else {
      authorizationState = .unknown
      return
    }

    let center = self.center
    let state = await withCheckedContinuation { continuation in
      center.getNotificationSettings { settings in
        continuation.resume(
          returning: NotificationAuthorizationMapper.state(for: settings.authorizationStatus))
      }
    }
    authorizationState = state
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

      center.add(request) { [weak self] error in
        guard let error else { return }
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
          self?.authorizationState = .failed(
            "Could not deliver a notification: \(message)")
        }
      }
    }
  }

  private func requestAuthorization() async throws {
    let center = self.center
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      center.requestAuthorization(options: [.alert, .sound]) { _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }
}
