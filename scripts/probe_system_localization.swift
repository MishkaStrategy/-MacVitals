import Foundation

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

guard let appPath = CommandLine.arguments.last,
  appPath.hasSuffix(".app"),
  let bundle = Bundle(path: appPath)
else {
  fail("Usage: localization-probe [-AppleLanguages '(en)'] /path/to/MacVitals.app")
}

let localizations = bundle.localizations.sorted()
let preferred = bundle.preferredLocalizations.first
let preferences = bundle.localizedString(
  forKey: "Preferences",
  value: "__MISSING__",
  table: "Localizable")

let payload: [String: Any] = [
  "available": localizations,
  "development": bundle.developmentLocalization ?? NSNull(),
  "preferred": preferred ?? NSNull(),
  "preferencesTitle": preferences,
  "processPreferredLanguages": Locale.preferredLanguages,
]

let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
