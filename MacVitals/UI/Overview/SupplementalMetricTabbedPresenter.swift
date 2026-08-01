import AppKit
import SwiftUI

private enum SupplementalMetricTab: String, CaseIterable, Identifiable {
  case overview
  case consumptionLeaders

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: return ConsumptionHistoryL10n.string("Overview")
    case .consumptionLeaders:
      return ConsumptionHistoryL10n.string("Consumption leaders")
    }
  }
}

struct SupplementalMetricTabbedContainer: View {
  @State private var selectedTab: SupplementalMetricTab = .overview
  @EnvironmentObject private var settings: SettingsStore
  @ObservedObject private var networkMonitor: NetworkTrafficMonitor
  @ObservedObject private var storageMonitor: StorageUsageMonitor

  let kind: SupplementalMetricDetailKind

  init(
    kind: SupplementalMetricDetailKind,
    networkMonitor: NetworkTrafficMonitor,
    storageMonitor: StorageUsageMonitor
  ) {
    self.kind = kind
    self.networkMonitor = networkMonitor
    self.storageMonitor = storageMonitor
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Picker("Section", selection: $selectedTab) {
          ForEach(SupplementalMetricTab.allCases) { tab in
            Text(tab.title).tag(tab)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 300)
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 8)

      Divider()

      switch selectedTab {
      case .overview:
        SupplementalMetricDetailView(
          kind: kind,
          networkMonitor: networkMonitor,
          storageMonitor: storageMonitor)
          .environmentObject(settings)
      case .consumptionLeaders:
        HistoricalConsumptionLeadersView(metric: kind.historicalConsumptionMetric)
          .padding(16)
          .frame(width: 740, height: 650)
      }
    }
  }
}

extension SupplementalMetricDetailKind {
  var historicalConsumptionMetric: HistoricalConsumptionMetric {
    switch self {
    case .network: return .network
    case .storage: return .disk
    }
  }
}

@MainActor
final class SupplementalMetricTabbedWindowPresenter: NSObject, NSWindowDelegate {
  static let shared = SupplementalMetricTabbedWindowPresenter()

  private var windowController: NSWindowController?

  func show(
    kind: SupplementalMetricDetailKind,
    settings: SettingsStore,
    networkMonitor: NetworkTrafficMonitor,
    storageMonitor: StorageUsageMonitor
  ) {
    let rootView = ThemedMetricDetailRoot(metric: kind.themeMetricKind) {
      SupplementalMetricTabbedContainer(
        kind: kind,
        networkMonitor: networkMonitor,
        storageMonitor: storageMonitor)
        .environmentObject(settings)
    }

    let hostingController = NSHostingController(rootView: rootView)
    let size = NSSize(width: 780, height: 730)

    if let window = windowController?.window {
      window.contentViewController = hostingController
      window.title = kind.title
      window.setContentSize(size)
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let window = NSWindow(contentViewController: hostingController)
    window.title = kind.title
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.setContentSize(size)
    window.minSize = NSSize(width: 680, height: 580)
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.delegate = self
    window.center()

    let controller = NSWindowController(window: window)
    windowController = controller
    controller.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    windowController = nil
  }
}
