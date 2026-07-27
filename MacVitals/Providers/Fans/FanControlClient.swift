import Combine
import Foundation
import Security
import ServiceManagement

nonisolated enum FanControlClientState: Sendable, Equatable {
  case monitoringOnly
  case notRegistered
  case approvalRequired
  case connecting
  case ready
  case unavailable(String)

  var canControl: Bool {
    self == .ready
  }

  var message: String {
    switch self {
    case .monitoringOnly:
      return L10n.string("Fan RPM monitoring is available. Control requires an approved signed helper.")
    case .notRegistered:
      return L10n.string("Fan control helper is not installed.")
    case .approvalRequired:
      return L10n.string("Administrator approval is required in Login Items.")
    case .connecting:
      return L10n.string("Checking the fan control helper…")
    case .ready:
      return L10n.string("Fan control helper is ready.")
    case .unavailable(let message):
      return message
    }
  }
}

nonisolated enum FanControlSigningIdentity {
  static func teamIdentifier() -> String? {
    var dynamicCode: SecCode?
    guard SecCodeCopySelf([], &dynamicCode) == errSecSuccess,
      let dynamicCode,
      SecCodeCheckValidity(dynamicCode, [], nil) == errSecSuccess
    else { return nil }

    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess,
      let staticCode
    else { return nil }

    var information: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
      let values = information as? [String: Any],
      let identifier = values[kSecCodeInfoIdentifier as String] as? String,
      identifier == "com.mishkacher.MacVitals",
      let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
      !team.isEmpty
    else { return nil }
    return team
  }

  static func hasTeamIdentifier() -> Bool {
    teamIdentifier() != nil
  }
}

@MainActor
final class FanControlClient: ObservableObject {
  @Published private(set) var state: FanControlClientState = .monitoringOnly
  @Published private(set) var operationInProgress = false
  @Published private(set) var lastMessage: String?

  private let service = SMAppService.daemon(plistName: FanControlServiceConstants.daemonPlistName)
  private var connection: NSXPCConnection?

  func refreshStatus() {
    guard FanControlSigningIdentity.hasTeamIdentifier() else {
      invalidateConnection()
      operationInProgress = false
      state = .monitoringOnly
      return
    }

    switch service.status {
    case .enabled:
      state = .connecting
      ensureConnection()
      verifyHelper()
    case .requiresApproval:
      invalidateConnection()
      operationInProgress = false
      state = .approvalRequired
    case .notRegistered:
      invalidateConnection()
      operationInProgress = false
      state = .notRegistered
    case .notFound:
      invalidateConnection()
      operationInProgress = false
      state = .unavailable(L10n.string("Fan control helper is missing from this app build."))
    @unknown default:
      invalidateConnection()
      operationInProgress = false
      state = .unavailable(L10n.string("Fan control helper status is unknown."))
    }
  }

  func prepareControl() {
    switch state {
    case .monitoringOnly:
      lastMessage = L10n.string(
        "This test build is not signed with a Developer Team identity, so macOS blocks privileged fan control. Monitoring remains available.")
    case .notRegistered:
      requestApproval()
    case .approvalRequired:
      openApprovalSettings()
    case .connecting:
      lastMessage = L10n.string("Checking the fan control helper…")
    case .ready:
      lastMessage = nil
    case .unavailable:
      refreshStatus()
    }
  }

  func requestApproval() {
    guard FanControlSigningIdentity.hasTeamIdentifier() else {
      state = .monitoringOnly
      lastMessage = L10n.string(
        "This test build is not signed with a Developer Team identity, so macOS blocks privileged fan control. Monitoring remains available.")
      return
    }
    do {
      try service.register()
      refreshStatus()
      if service.status == .requiresApproval {
        SMAppService.openSystemSettingsLoginItems()
      }
    } catch {
      refreshStatus()
      lastMessage = error.localizedDescription
    }
  }

  func openApprovalSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  func setBoost(fan: FanReading, requestedRPM: Double, leaseSeconds: TimeInterval = 15 * 60) {
    guard state.canControl else {
      prepareControl()
      return
    }
    do {
      let plan = try FanControlSafetyPolicy.plan(
        fan: fan,
        requestedRPM: requestedRPM,
        leaseSeconds: leaseSeconds,
        thermalSeverity: FanThermalSeverity(ProcessInfo.processInfo.thermalState))
      guard let helper = proxy() else {
        handleMissingProxy()
        return
      }
      operationInProgress = true
      helper.setFanBoost(
        index: plan.fanIndex,
        requestedRPM: plan.targetRPM,
        leaseSeconds: plan.leaseSeconds
      ) { [weak self] success, appliedRPM, message in
        Task { @MainActor in
          self?.operationInProgress = false
          self?.lastMessage = success
            ? L10n.format("Cooling boost set to %d RPM.", Int(appliedRPM.rounded()))
            : message ?? L10n.string("Fan control request failed.")
          if success { self?.state = .ready }
        }
      }
    } catch {
      operationInProgress = false
      lastMessage = error.localizedDescription
    }
  }

  func setAutomatic(fanIndex: Int) {
    guard state.canControl else {
      prepareControl()
      return
    }
    guard let helper = proxy() else {
      handleMissingProxy()
      return
    }
    operationInProgress = true
    helper.setFanAutomatic(index: fanIndex) { [weak self] success, message in
      Task { @MainActor in
        self?.operationInProgress = false
        self?.lastMessage = success
          ? L10n.string("System automatic fan control restored.")
          : message ?? L10n.string("Could not restore automatic fan control.")
        if success { self?.state = .ready }
      }
    }
  }

  func setAllAutomatic() {
    guard state.canControl else {
      prepareControl()
      return
    }
    guard let helper = proxy() else {
      handleMissingProxy()
      return
    }
    operationInProgress = true
    helper.setAllFansAutomatic { [weak self] success, message in
      Task { @MainActor in
        self?.operationInProgress = false
        self?.lastMessage = success
          ? L10n.string("System automatic fan control restored for all fans.")
          : message ?? L10n.string("Could not restore automatic fan control.")
        if success { self?.state = .ready }
      }
    }
  }

  func invalidateConnection() {
    connection?.invalidationHandler = nil
    connection?.interruptionHandler = nil
    connection?.invalidate()
    connection = nil
  }

  private func ensureConnection() {
    guard connection == nil else { return }
    let connection = NSXPCConnection(
      machServiceName: FanControlServiceConstants.machServiceName,
      options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: FanControlXPCProtocol.self)
    connection.interruptionHandler = { [weak self] in
      Task { @MainActor in
        self?.operationInProgress = false
        self?.state = .unavailable(
          L10n.string("Fan control helper connection was interrupted."))
        self?.lastMessage = L10n.string("Fan control helper connection was interrupted.")
      }
    }
    connection.invalidationHandler = { [weak self] in
      Task { @MainActor in
        self?.operationInProgress = false
        self?.connection = nil
        self?.refreshStatus()
      }
    }
    connection.resume()
    self.connection = connection
  }

  private func proxy() -> FanControlXPCProtocol? {
    ensureConnection()
    return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
      Task { @MainActor in
        self?.operationInProgress = false
        self?.state = .unavailable(error.localizedDescription)
        self?.lastMessage = error.localizedDescription
      }
    } as? FanControlXPCProtocol
  }

  private func verifyHelper() {
    guard let helper = proxy() else {
      handleMissingProxy()
      return
    }
    helper.status { [weak self] available, message in
      Task { @MainActor in
        self?.operationInProgress = false
        if available {
          self?.state = .ready
          self?.lastMessage = nil
        } else {
          self?.state = .unavailable(
            message ?? L10n.string("Fan control helper did not pass its self-check."))
        }
      }
    }
  }

  private func handleMissingProxy() {
    operationInProgress = false
    let message = L10n.string("Could not connect to the fan control helper.")
    state = .unavailable(message)
    lastMessage = message
  }
}
