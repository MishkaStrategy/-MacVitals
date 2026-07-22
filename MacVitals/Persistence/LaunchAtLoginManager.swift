import Foundation
import ServiceManagement

nonisolated enum LaunchAtLoginState: Equatable, Sendable {
  case disabled
  case enabled
  case requiresApproval
  case unavailable
  case failed(String)

  var isEnabled: Bool {
    if case .enabled = self { return true }
    return false
  }

  var message: String? {
    switch self {
    case .disabled, .enabled:
      return nil
    case .requiresApproval:
      return L10n.string("Approval is required in System Settings › General › Login Items.")
    case .unavailable:
      return L10n.string(
        "Launch at login is unavailable for this app installation. Move MacVitals to Applications and try again.")
    case .failed(let message):
      return message
    }
  }
}

protocol LaunchAtLoginManaging: Sendable {
  var state: LaunchAtLoginState { get }
  func setEnabled(_ enabled: Bool) throws
}

nonisolated enum LaunchAtLoginStateMapper {
  static func state(for status: SMAppService.Status) -> LaunchAtLoginState {
    switch status {
    case .notRegistered: return .disabled
    case .enabled: return .enabled
    case .requiresApproval: return .requiresApproval
    case .notFound: return .unavailable
    @unknown default: return .unavailable
    }
  }
}

struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
  var state: LaunchAtLoginState {
    LaunchAtLoginStateMapper.state(for: SMAppService.mainApp.status)
  }

  func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}
