import AppKit
import Combine
import Foundation
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
    case .cpu: return L10n.string("CPU")
    case .gpu: return L10n.string("GPU")
    case .memory: return L10n.string("Memory")
    case .battery: return L10n.string("Battery")
    case .adapterPower: return L10n.string("Adapter power")
    case .powerStatus: return L10n.string("Power status")
    }
  }
}

nonisolated enum MenuPreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case minimal, performance, power, battery, everything, custom

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .minimal: return L10n.string("Minimal")
    case .performance: return L10n.string("Performance")
    case .power: return L10n.string("Power")
    case .battery: return L10n.string("Battery")
    case .everything: return L10n.string("Everything")
    case .custom: return L10n.string("Custom")
    }
  }

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

nonisolated enum MenuPresetResolution {
  static func resolve(
    storedPreset: MenuPreset,
    metrics: [MenuMetric],
    preserveExplicitCustom: Bool
  ) -> MenuPreset {
    let normalized = MenuLayoutRules.normalized(metrics)
    if preserveExplicitCustom, storedPreset == .custom { return .custom }
    if storedPreset != .custom, storedPreset.metrics == normalized { return storedPreset }
    return MenuPreset.allCases.first {
      $0 != .custom && $0.metrics == normalized
    } ?? .custom
  }

  static func shouldPersistCorrection(
    storedRawValue: String?,
    resolvedPreset: MenuPreset,
    hasValidStoredConfiguration: Bool
  ) -> Bool {
    hasValidStoredConfiguration && storedRawValue != resolvedPreset.rawValue
  }
}

nonisolated enum MenuConfigurationPersistence {
  static let currentSchemaVersion = 1

  private struct StoredMenuConfiguration: Codable {
    let schemaVersion: Int
    let enabledMetricIDs: [String]
  }

  static func decode(_ data: Data) -> [MenuMetric]? {
    guard let stored = try? JSONDecoder().decode(StoredMenuConfiguration.self, from: data),
      stored.schemaVersion == currentSchemaVersion
    else { return nil }

    return MenuLayoutRules.normalized(
      stored.enabledMetricIDs.compactMap { MenuMetric(rawValue: $0) })
  }

  static func encode(_ metrics: [MenuMetric]) -> Data? {
    let stored = StoredMenuConfiguration(
      schemaVersion: currentSchemaVersion,
      enabledMetricIDs: MenuLayoutRules.normalized(metrics).map(\.rawValue))
    return try? JSONEncoder().encode(stored)
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
    didSet {
      let normalized = SamplingIntervalPolicy.normalized(samplingInterval)
      if normalized != samplingInterval {
        samplingInterval = normalized
        return
      }
      UserDefaults.standard.set(normalized, forKey: Keys.samplingInterval)
    }
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
  @Published var notificationsEnabled: Bool {
    didSet { UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
  }
  @Published var memoryAlertThreshold: Double {
    didSet {
      let normalized = SettingsNumericPolicy.memoryAlertThreshold(memoryAlertThreshold)
      if normalized != memoryAlertThreshold {
        memoryAlertThreshold = normalized
        return
      }
      UserDefaults.standard.set(normalized, forKey: Keys.memoryAlertThreshold)
    }
  }
  @Published var lowBatteryAlertThreshold: Double {
    didSet {
      let normalized = SettingsNumericPolicy.lowBatteryAlertThreshold(lowBatteryAlertThreshold)
      if normalized != lowBatteryAlertThreshold {
        lowBatteryAlertThreshold = normalized
        return
      }
      UserDefaults.standard.set(normalized, forKey: Keys.lowBatteryAlertThreshold)
    }
  }
  @Published private(set) var launchAtLoginState: LaunchAtLoginState = .disabled
  @Published private(set) var notificationAuthorizationState: NotificationAuthorizationState =
    .unknown

  private let launchAtLoginManager: any LaunchAtLoginManaging

  var launchAtLogin: Bool { launchAtLoginState.isEnabled }

  var hiddenMetrics: [MenuMetric] {
    MenuMetric.allCases.filter { !enabledMetrics.contains($0) }
  }

  init(launchAtLoginManager: any LaunchAtLoginManaging = SystemLaunchAtLoginManager()) {
    self.launchAtLoginManager = launchAtLoginManager

    let defaults = UserDefaults.standard
    samplingInterval = SamplingIntervalPolicy.normalized(
      defaults.double(forKey: Keys.samplingInterval))
    showInDock = defaults.bool(forKey: Keys.showInDock)
    reducedMotion = defaults.bool(forKey: Keys.reducedMotion)
    notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
    memoryAlertThreshold = SettingsNumericPolicy.memoryAlertThreshold(
      defaults.double(forKey: Keys.memoryAlertThreshold))
    lowBatteryAlertThreshold = SettingsNumericPolicy.lowBatteryAlertThreshold(
      defaults.double(forKey: Keys.lowBatteryAlertThreshold))

    let storedPresetRawValue = defaults.string(forKey: Keys.selectedPreset)
    let storedPreset: MenuPreset
    if let rawPreset = storedPresetRawValue,
      let preset = MenuPreset(rawValue: rawPreset)
    {
      storedPreset = preset
    } else {
      storedPreset = .performance
    }

    let storedConfigurationData = defaults.data(forKey: Keys.menuConfiguration)
    let storedMetrics: [MenuMetric]? =
      storedConfigurationData.flatMap { MenuConfigurationPersistence.decode($0) }
    let initialMetrics =
      storedMetrics
      ?? (storedPreset == .custom ? MenuPreset.performance.metrics : storedPreset.metrics)
    let initialPreset = MenuPresetResolution.resolve(
      storedPreset: storedPreset,
      metrics: initialMetrics,
      preserveExplicitCustom: storedMetrics != nil)

    selectedPreset = initialPreset
    enabledMetrics = initialMetrics
    if MenuPresetResolution.shouldPersistCorrection(
      storedRawValue: storedPresetRawValue,
      resolvedPreset: initialPreset,
      hasValidStoredConfiguration: storedMetrics != nil)
    {
      defaults.set(initialPreset.rawValue, forKey: Keys.selectedPreset)
    }
    refreshLaunchAtLoginState()
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
      try launchAtLoginManager.setEnabled(enabled)
      refreshLaunchAtLoginState()
    } catch {
      launchAtLoginState = .failed(
        L10n.format("Could not update launch at login: %@", error.localizedDescription))
    }
  }

  func refreshLaunchAtLoginState() {
    launchAtLoginState = launchAtLoginManager.state
  }

  func setNotificationAuthorizationState(_ state: NotificationAuthorizationState) {
    notificationAuthorizationState = state
  }

  func reset() {
    selectedPreset = .performance
    enabledMetrics = MenuPreset.performance.metrics
    samplingInterval = SamplingIntervalPolicy.defaultValue
    reducedMotion = false
    notificationsEnabled = false
    memoryAlertThreshold = SettingsNumericPolicy.defaultMemoryAlertThreshold
    lowBatteryAlertThreshold = SettingsNumericPolicy.defaultLowBatteryAlertThreshold
  }

  private func persistMenuConfiguration() {
    if let data = MenuConfigurationPersistence.encode(enabledMetrics) {
      UserDefaults.standard.set(data, forKey: Keys.menuConfiguration)
    }
  }

  private enum Keys {
    static let menuConfiguration = "menuConfiguration.v1"
    static let selectedPreset = "selectedPreset"
    static let samplingInterval = "samplingInterval"
    static let showInDock = "showInDock"
    static let reducedMotion = "reducedMotion"
    static let notificationsEnabled = "notificationsEnabled"
    static let memoryAlertThreshold = "memoryAlertThreshold"
    static let lowBatteryAlertThreshold = "lowBatteryAlertThreshold"
  }
}
