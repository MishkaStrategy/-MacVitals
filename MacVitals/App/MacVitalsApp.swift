import SwiftUI

@main
struct MacVitalsApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      ThemedPreferencesRootView()
        .environmentObject(appDelegate.coordinator)
        .environmentObject(appDelegate.settings)
        .environmentObject(appDelegate.fanControl)
        .frame(minWidth: 860, minHeight: 700)
    }
  }
}
