import Combine
import Foundation

nonisolated enum StatusBarPetL10n {
  private static let tableName = "StatusBarPet"

  static func string(_ key: String) -> String {
    NSLocalizedString(key, tableName: tableName, bundle: .main, comment: "")
  }
}

@MainActor
final class StatusBarPetSettingsStore: ObservableObject {
  nonisolated static let defaultsKey = "statusBarPetConfiguration.v1"
  nonisolated static let runtimeSmokeEnvironmentKey =
    "MACVITALS_STATUS_BAR_PET_RUNTIME_SMOKE"

  @Published var configuration: StatusBarPetConfiguration {
    didSet {
      let normalized = StatusBarPetConfigurationPolicy.normalized(configuration)
      if normalized != configuration {
        configuration = normalized
        return
      }
      persist()
    }
  }

  private let defaults: UserDefaults

  init(
    defaults: UserDefaults = .standard,
    runtimeSmokeEnabled: Bool = ProcessInfo.processInfo.environment[
      Self.runtimeSmokeEnvironmentKey
    ] == "1"
  ) {
    self.defaults = defaults

    var resolvedConfiguration = defaults.data(forKey: Self.defaultsKey)
      .flatMap(StatusBarPetConfigurationPersistence.decode)
      ?? .electricDragon

    if runtimeSmokeEnabled {
      resolvedConfiguration.isEnabled = true
      resolvedConfiguration.roamEnabled = true
      resolvedConfiguration.cursorInteractionEnabled = false
      resolvedConfiguration.respectReducedMotion = false
      resolvedConfiguration.size = .medium
      resolvedConfiguration.movementSpeed = 1.4
      resolvedConfiguration.sparkIntensity = 0.75
    }

    configuration = StatusBarPetConfigurationPolicy.normalized(resolvedConfiguration)
  }

  func reset() {
    configuration = .electricDragon
  }

  func toggleEnabled() {
    configuration.isEnabled.toggle()
  }

  private func persist() {
    guard let data = StatusBarPetConfigurationPersistence.encode(configuration) else { return }
    defaults.set(data, forKey: Self.defaultsKey)
  }
}
