import Foundation

nonisolated enum L10n {
  static func string(_ key: String, comment: String = "") -> String {
    NSLocalizedString(key, bundle: .main, comment: comment)
  }

  static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(
      format: string(key),
      locale: Locale.current,
      arguments: arguments)
  }
}
