import Foundation

nonisolated enum L10n {
  private static let missingSentinel = "__MACVITALS_MISSING_LOCALIZATION__"

  static func string(_ key: String, comment: String = "") -> String {
    let modern = Bundle.main.localizedString(
      forKey: key,
      value: missingSentinel,
      table: "UXV2")
    if modern != missingSentinel { return modern }
    return NSLocalizedString(key, bundle: .main, comment: comment)
  }

  static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(
      format: string(key),
      locale: Locale.current,
      arguments: arguments)
  }
}
