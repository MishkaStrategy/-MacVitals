import SwiftUI

@main
struct MacVitalsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesView()
                .environmentObject(appDelegate.coordinator)
                .environmentObject(appDelegate.settings)
                .frame(minWidth: 620, minHeight: 520)
        }
    }
}
