import Foundation

private func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

private struct Arguments {
  let preferences: [String]
  let source: String
  let appPath: String
}

private func parseArguments() -> Arguments {
  let values = Array(CommandLine.arguments.dropFirst())
  guard let appPath = values.last, appPath.hasSuffix(".app") else {
    fail(
      "Usage: localization-probe (--system | --preferences lang[,lang]) "
        + "/path/to/MacVitals.app")
  }

  if values.count == 2, values[0] == "--system" {
    return Arguments(
      preferences: Locale.preferredLanguages,
      source: "system",
      appPath: appPath)
  }

  if values.count == 3, values[0] == "--preferences" {
    let preferences = values[1]
      .split(separator: ",")
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !preferences.isEmpty else { fail("At least one preferred language is required") }
    return Arguments(preferences: preferences, source: "explicit", appPath: appPath)
  }

  fail(
    "Usage: localization-probe (--system | --preferences lang[,lang]) "
      + "/path/to/MacVitals.app")
}

let arguments = parseArguments()
guard let appBundle = Bundle(path: arguments.appPath) else {
  fail("Could not load application bundle")
}

let available = Array(Set(appBundle.localizations)).sorted()
let selected = Bundle.preferredLocalizations(
  from: available,
  forPreferences: arguments.preferences
).first ?? appBundle.developmentLocalization

guard let selected else { fail("No supported localization could be selected") }
guard let localizationURL = appBundle.url(forResource: selected, withExtension: "lproj"),
  let localizationBundle = Bundle(url: localizationURL)
else {
  fail("Selected localization resources are missing: \(selected)")
}

let preferencesTitle = localizationBundle.localizedString(
  forKey: "Preferences",
  value: "__MISSING__",
  table: "Localizable")

let payload: [String: Any] = [
  "available": available,
  "development": appBundle.developmentLocalization ?? NSNull(),
  "requestedPreferences": arguments.preferences,
  "preferenceSource": arguments.source,
  "selected": selected,
  "preferencesTitle": preferencesTitle,
]

let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
