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

@MainActor
final class SettingsStore: ObservableObject {
  @Published var enabledMetrics: [MenuMetric] { didSet { persist() } }
  @Published var selectedPreset: MenuPreset { didSet { applyPreset(selectedPreset) } }
  @Published var samplingInterval: Double {
    didSet { UserDefaults.standard.set(samplingInterval, forKey: "samplingInterval") }
  }
  @Published var showInDock: Bool {
    didSet {
      NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
      UserDefaults.standard.set(showInDock, forKey: "showInDock")
    }
  }
  @Published var reducedMotion: Bool {
    didSet { UserDefaults.standard.set(reducedMotion, forKey: "reducedMotion") }
  }
  @Published var launchAtLogin: Bool = false

  init() {
    samplingInterval = UserDefaults.standard.double(forKey: "samplingInterval").nonZero ?? 2
    showInDock = UserDefaults.standard.bool(forKey: "showInDock")
    reducedMotion = UserDefaults.standard.bool(forKey: "reducedMotion")
    selectedPreset = .performance
    if let data = UserDefaults.standard.data(forKey: "enabledMetrics"),
      let decoded = try? JSONDecoder().decode([MenuMetric].self, from: data), !decoded.isEmpty
    {
      enabledMetrics = decoded
    } else {
      enabledMetrics = MenuPreset.performance.metrics
    }
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  func applyPreset(_ preset: MenuPreset) {
    guard preset != .custom else { return }
    enabledMetrics = preset.metrics
  }

  func move(from source: IndexSet, to destination: Int) {
    enabledMetrics.move(fromOffsets: source, toOffset: destination)
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
    } catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
  }

  func reset() {
    selectedPreset = .performance
    samplingInterval = 2
    reducedMotion = false
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(enabledMetrics) {
      UserDefaults.standard.set(data, forKey: "enabledMetrics")
    }
  }
}

extension Double { fileprivate var nonZero: Double? { self > 0 ? self : nil } }
