import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private let coordinator: MetricsCoordinator
    private let settings: SettingsStore

    init(coordinator: MetricsCoordinator, settings: SettingsStore) {
        self.coordinator = coordinator; self.settings = settings
        super.init()
        let root = OverviewView().environmentObject(coordinator).environmentObject(settings)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 390, height: 560)
        if let button = statusItem.button {
            button.target = self; button.action = #selector(togglePopover); button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "MacVitals"
        }
        coordinator.$snapshot.combineLatest(settings.$enabledMetrics)
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot, metrics in self?.render(snapshot: snapshot, metrics: metrics) }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(); return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: NSLocalizedString("Open MacVitals", comment: ""), action: #selector(openPopover), keyEquivalent: "")
        menu.addItem(withTitle: NSLocalizedString("Preferences…", comment: ""), action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: NSLocalizedString("Quit MacVitals", comment: ""), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
    }

    @objc private func openPopover() { togglePopover() }
    @objc private func openPreferences() { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func render(snapshot: SystemSnapshot, metrics: [MenuMetric]) {
        let parts = metrics.compactMap { metric -> String? in
            switch metric {
            case .cpu: return snapshot.cpu.value.map { "CPU \(Int($0.total.rounded()))%" }
            case .gpu: return snapshot.gpu.value?.systemUtilizationPercent.map { "GPU \(Int($0.rounded()))%" }
            case .memory: return snapshot.memory.value.map { "RAM \(Int($0.usedPercent.rounded()))%" }
            case .battery: return snapshot.battery.value?.percentage.map { "🔋 \(Int($0.rounded()))%" }
            case .adapterPower: return snapshot.adapter.value?.ratedPowerWatts.map { "⚡ \(Int($0.rounded())) W" }
            case .powerStatus: return snapshot.power.value.map { icon(for: $0.status) }
            }
        }
        statusItem.button?.title = parts.isEmpty ? "◉" : parts.joined(separator: " · ")
        statusItem.length = NSStatusItem.variableLength
    }

    private func icon(for status: PowerSufficiencyStatus) -> String {
        switch status { case .insufficient: return "⚠︎"; case .borderline: return "◐"; case .chargingBattery: return "↯";
        case .sufficient: return "✓"; case .notConnected: return "🔋"; case .sensorConflict: return "!?"; default: return "?" }
    }
}
