import Foundation

nonisolated enum NetworkL10n {
  static func string(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: "Network")
  }
}
