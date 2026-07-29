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
      return L10n.string("Checking notification permission…")
    case .notDetermined:
      return L10n.string("macOS will ask for notification permission when alerts are enabled.")
    case .denied:
      return L10n.string(
        "Notifications are disabled in System Settings › Notifications › MacVitals.")
    case .authorized:
      return nil
    case .provisional:
      return L10n.string("Notifications are authorized for quiet delivery.")
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
  private var authorizationFlowTask: Task<Void, Never>?
  private var authorizationRequestGate = NotificationAuthorizationRequestGate()
  private var authorizationRefreshGate = NotificationAuthorizationRefreshGate()
  private var deliveryCallbackGate = NotificationDeliveryCallbackGate()
  private var deliveryRetryGate = NotificationDeliveryRetryGate()
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func setEnabled(
    _ enabled: Bool,
    memoryAlertsEnabled: Bool,
    memoryThreshold: Double,
    lowBatteryAlertsEnabled: Bool,
    lowBatteryThreshold: Double
  ) {
    let wasEnabled = self.enabled
    self.enabled = enabled
    policy.updateConfiguration(
      .init(
        memoryAlertsEnabled: memoryAlertsEnabled,
        lowBatteryAlertsEnabled: lowBatteryAlertsEnabled,
        memoryThresholdPercent: memoryThreshold,
        lowBatteryThresholdPercent: lowBatteryThreshold))

    if enabled != wasEnabled {
      deliveryCallbackGate.invalidate()
    }

    guard enabled else {
      authorizationFlowTask?.cancel()
      authorizationFlowTask = nil
      authorizationRefreshGate.invalidate()
      deliveryRetryGate.reset()
      policy.reset()
      authorizationState = .unknown
      return
    }

    guard !wasEnabled else { return }
    startAuthorizationFlow()
  }

  func refreshAuthorizationState() async {
    guard enabled else {
      authorizationRefreshGate.invalidate()
      authorizationState = .unknown
      return
    }

    let token = authorizationRefreshGate.begin()
    let center = self.center
    let state = await withCheckedContinuation { continuation in
      center.getNotificationSettings { settings in
        continuation.resume(
          returning: NotificationAuthorizationMapper.state(for: settings.authorizationStatus))
      }
    }
    guard enabled,
      !Task.isCancelled,
      authorizationRefreshGate.isCurrent(token)
    else { return }

    authorizationState = state
    guard state == .notDetermined,
      authorizationRequestGate.begin()
    else { return }

    defer { authorizationRequestGate.finish() }

    do {
      try await requestAuthorization()
      guard enabled else { return }
      startAuthorizationFlow()
    } catch {
      guard enabled else { return }
      if authorizationRefreshGate.isCurrent(token)
        || authorizationState == .unknown
        || authorizationState == .notDetermined
      {
        authorizationState = .failed(
          L10n.format("Could not request notification permission: %@", error.localizedDescription))
      }
    }
  }

  func process(snapshot: SystemSnapshot) {
    guard enabled, authorizationState.canDeliver else { return }

    let events = policy.evaluate(snapshot: snapshot)
    let attemptDate = Date()
    for event in events {
      guard deliveryRetryGate.canAttempt(event.kind, at: attemptDate) else {
        policy.markDeliveryFailed(event.kind)
        continue
      }

      let content = UNMutableNotificationContent()
      content.title = event.title
      content.body = event.message
      content.sound = .default
      let request = UNNotificationRequest(
        identifier: "macvitals.\(event.kind.rawValue).\(UUID().uuidString)",
        content: content,
        trigger: nil)
      let callbackToken = deliveryCallbackGate.token

      center.add(request) { [weak self] error in
        guard let error else { return }
        let failedAt = Date()
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
          guard let self,
            self.enabled,
            self.deliveryCallbackGate.isCurrent(callbackToken)
          else { return }

          self.deliveryRetryGate.markFailed(event.kind, at: failedAt)
          self.policy.markDeliveryFailed(event.kind)
          self.authorizationState = .failed(
            L10n.format("Could not deliver a notification: %@", message))
          self.startAuthorizationFlow()
        }
      }
    }
  }

  private func startAuthorizationFlow() {
    authorizationFlowTask?.cancel()
    authorizationFlowTask = Task { [weak self] in
      await self?.refreshAuthorizationState()
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
