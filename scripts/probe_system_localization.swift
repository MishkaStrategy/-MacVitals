import Foundation

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

private func parseAppleLanguages(_ raw: String) -> [String] {
  let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  let unwrapped = trimmed
    .trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
  return unwrapped
    .split(separator: ",")
    .map {
      String($0)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
    .filter { !$0.isEmpty }
}

let values = Array(CommandLine.arguments.dropFirst())
let appPath: String
let requestedPreferences: [String]
let preferenceSource: String

if values.count == 1 {
  appPath = values[0]
  requestedPreferences = Locale.preferredLanguages
  preferenceSource = "system"
} else if values.count == 3, values[0] == "-AppleLanguages" {
  appPath = values[2]
  requestedPreferences = parseAppleLanguages(values[1])
  preferenceSource = "explicit"
} else if values.count == 2, values[0] == "--system" {
  appPath = values[1]
  requestedPreferences = Locale.preferredLanguages
  preferenceSource = "system"
} else if values.count == 3, values[0] == "--preferences" {
  appPath = values[2]
  requestedPreferences = values[1]
    .split(separator: ",")
    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
  preferenceSource = "explicit"
} else {
  fail(
    "Usage: localization-probe [-AppleLanguages '(en)'] /path/to/MacVitals.app")
}

guard appPath.hasSuffix(".app"), let appBundle = Bundle(path: appPath) else {
  fail("Could not load application bundle")
}
guard !requestedPreferences.isEmpty else {
  fail("At least one preferred language is required")
}

let available = Array(Set(appBundle.localizations)).sorted()
let preferred = Bundle.preferredLocalizations(
  from: available,
  forPreferences: requestedPreferences
).first ?? appBundle.developmentLocalization

guard let preferred else { fail("No supported localization could be selected") }
guard let localizationURL = appBundle.url(forResource: preferred, withExtension: "lproj"),
  let localizationBundle = Bundle(url: localizationURL)
else {
  fail("Selected localization resources are missing: \(preferred)")
}

let preferencesTitle = localizationBundle.localizedString(
  forKey: "Preferences",
  value: "__MISSING__",
  table: "Localizable")

let payload: [String: Any] = [
  "available": available,
  "development": appBundle.developmentLocalization ?? NSNull(),
  "preferred": preferred,
  "preferencesTitle": preferencesTitle,
  "requestedPreferences": requestedPreferences,
  "preferenceSource": preferenceSource,
  "processPreferredLanguages": Locale.preferredLanguages,
]

let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
