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

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    configuration = defaults.data(forKey: Self.defaultsKey)
      .flatMap(StatusBarPetConfigurationPersistence.decode)
      ?? .electricDragon
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
