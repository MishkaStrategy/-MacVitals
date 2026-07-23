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

nonisolated struct NotificationAuthorizationRequestGate: Sendable {
  private(set) var isInFlight = false

  mutating func begin() -> Bool {
    guard !isInFlight else { return false }
    isInFlight = true
    return true
  }

  mutating func finish() {
    isInFlight = false
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
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func setEnabled(
    _ enabled: Bool,
    memoryThreshold: Double,
    lowBatteryThreshold: Double
  ) {
    let wasEnabled = self.enabled
    self.enabled = enabled
    policy.updateConfiguration(
      .init(
        memoryThresholdPercent: memoryThreshold,
        lowBatteryThresholdPercent: lowBatteryThreshold))

    guard enabled else {
      authorizationFlowTask?.cancel()
      authorizationFlowTask = nil
      policy.reset()
      authorizationState = .unknown
      return
    }

    guard !wasEnabled else { return }
    startAuthorizationFlow()
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
    guard enabled else { return }
    authorizationState = state
  }

  func process(snapshot: SystemSnapshot) {
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
          guard self?.enabled == true else { return }
          self?.authorizationState = .failed(
            L10n.format("Could not deliver a notification: %@", message))
        }
      }
    }
  }

  private func startAuthorizationFlow() {
    authorizationFlowTask?.cancel()
    authorizationFlowTask = Task { [weak self] in
      guard let self else { return }
      await refreshAuthorizationState()
      guard enabled, !Task.isCancelled,
        authorizationState == .notDetermined,
        authorizationRequestGate.begin()
      else { return }

      defer { authorizationRequestGate.finish() }

      do {
        try await requestAuthorization()
        guard enabled else { return }
        await refreshAuthorizationState()
      } catch {
        guard enabled else { return }
        authorizationState = .failed(
          L10n.format("Could not request notification permission: %@", error.localizedDescription))
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
