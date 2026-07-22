import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

nonisolated enum MenuMetric: String, Codable, CaseIterable, Identifiable, Sendable {
  case cpu, gpu, memory, battery, adapterPower, powerStatus

  var id: String { rawValue }

  var defaultSymbol: String {
    switch self {
    case .cpu: return "cpu"
    case .gpu: return "rectangle.3.group"
    case .memory: return "memorychip"
    case .battery: return "battery.75percent"
    case .adapterPower: return "bolt.fill"
    case .powerStatus: return "gauge.with.dots.needle.67percent"
    }
  }

  var displayName: String {
    switch self {
    case .cpu: return "CPU"
    case .gpu: return "GPU"
    case .memory: return "Memory"
    case .battery: return "Battery"
    case .adapterPower: return "Adapter power"
    case .powerStatus: return "Power status"
    }
  }
}

nonisolated enum MenuPreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case minimal, performance, power, battery, everything, custom

  var id: String { rawValue }

  var metrics: [MenuMetric] {
    switch self {
    case .minimal: return [.powerStatus, .battery]
    case .performance: return [.cpu, .gpu, .memory]
    case .power: return [.adapterPower, .powerStatus, .battery]
    case .battery: return [.battery, .powerStatus]
    case .everything: return MenuMetric.allCases
    case .custom: return []
    }
  }
}

nonisolated enum MenuLayoutRules {
  static func normalized(_ metrics: [MenuMetric]) -> [MenuMetric] {
    var seen = Set<MenuMetric>()
    return metrics.filter { seen.insert($0).inserted }
  }

  static func setting(_ metric: MenuMetric, enabled: Bool, in metrics: [MenuMetric])
    -> [MenuMetric]
  {
    var result = normalized(metrics)
    if enabled {
      if !result.contains(metric) { result.append(metric) }
    } else {
      result.removeAll { $0 == metric }
    }
    return result
  }
}

private struct StoredMenuConfiguration: Codable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let enabledMetricIDs: [String]

  init(metrics: [MenuMetric]) {
    schemaVersion = Self.currentSchemaVersion
    enabledMetricIDs = MenuLayoutRules.normalized(metrics).map(\.rawValue)
  }

  var metrics: [MenuMetric] {
    MenuLayoutRules.normalized(enabledMetricIDs.compactMap(MenuMetric.init(rawValue:)))
  }
}

@MainActor
final class SettingsStore: ObservableObject {
  @Published var enabledMetrics: [MenuMetric] { didSet { persistMenuConfiguration() } }
  @Published var selectedPreset: MenuPreset {
    didSet {
      UserDefaults.standard.set(selectedPreset.rawValue, forKey: Keys.selectedPreset)
      applyPreset(selectedPreset)
    }
  }
  @Published var samplingInterval: Double {
    didSet { UserDefaults.standard.set(samplingInterval, forKey: Keys.samplingInterval) }
  }
  @Published var showInDock: Bool {
    didSet {
      NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
      UserDefaults.standard.set(showInDock, forKey: Keys.showInDock)
    }
  }
  @Published var reducedMotion: Bool {
    didSet { UserDefaults.standard.set(reducedMotion, forKey: Keys.reducedMotion) }
  }
  @Published var launchAtLogin: Bool = false

  var hiddenMetrics: [MenuMetric] {
    MenuMetric.allCases.filter { !enabledMetrics.contains($0) }
  }

  init() {
    let defaults = UserDefaults.standard
    samplingInterval = defaults.double(forKey: Keys.samplingInterval).nonZero ?? 2
    showInDock = defaults.bool(forKey: Keys.showInDock)
    reducedMotion = defaults.bool(forKey: Keys.reducedMotion)

    if let rawPreset = defaults.string(forKey: Keys.selectedPreset),
      let preset = MenuPreset(rawValue: rawPreset)
    {
      selectedPreset = preset
    } else {
      selectedPreset = .performance
    }

    if let data = defaults.data(forKey: Keys.menuConfiguration),
      let stored = try? JSONDecoder().decode(StoredMenuConfiguration.self, from: data)
    {
      enabledMetrics = stored.metrics
    } else {
      enabledMetrics =
        selectedPreset == .custom
        ? MenuPreset.performance.metrics
        : selectedPreset.metrics
    }

    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  func applyPreset(_ preset: MenuPreset) {
    guard preset != .custom else { return }
    enabledMetrics = preset.metrics
  }

  func setMetric(_ metric: MenuMetric, enabled: Bool) {
    enabledMetrics = MenuLayoutRules.setting(metric, enabled: enabled, in: enabledMetrics)
    selectedPreset = .custom
  }

  func move(from source: IndexSet, to destination: Int) {
    enabledMetrics.move(fromOffsets: source, toOffset: destination)
    enabledMetrics = MenuLayoutRules.normalized(enabledMetrics)
    selectedPreset = .custom
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLogin = SMAppService.mainApp.status == .enabled
    } catch {
      launchAtLogin = SMAppService.mainApp.status == .enabled
    }
  }

  func reset() {
    selectedPreset = .performance
    enabledMetrics = MenuPreset.performance.metrics
    samplingInterval = 2
    reducedMotion = false
  }

  private func persistMenuConfiguration() {
    let stored = StoredMenuConfiguration(metrics: enabledMetrics)
    if let data = try? JSONEncoder().encode(stored) {
      UserDefaults.standard.set(data, forKey: Keys.menuConfiguration)
    }
  }

  private enum Keys {
    static let menuConfiguration = "menuConfiguration.v1"
    static let selectedPreset = "selectedPreset"
    static let samplingInterval = "samplingInterval"
    static let showInDock = "showInDock"
    static let reducedMotion = "reducedMotion"
  }
}

extension Double {
  fileprivate var nonZero: Double? { self > 0 ? self : nil }
}
