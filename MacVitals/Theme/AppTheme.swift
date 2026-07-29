import AppKit
import Combine
import Foundation
import SwiftUI

nonisolated enum ColorSchemeStyle: String, Codable, CaseIterable, Identifiable, Sendable {
  case duotone
  case multicolor

  var id: String { rawValue }
}

nonisolated enum MetricKind: String, CaseIterable, Identifiable, Sendable {
  case cpu
  case memory
  case gpu
  case battery
  case systemPower
  case temperature
  case fans
  case neutral

  var id: String { rawValue }
}

nonisolated enum ThemeColorToken: String, Codable, Equatable, Sendable {
  case blue
  case purple
  case green
  case mint
  case orange
  case redOrange
  case cyan
  case gray
}

nonisolated struct ThemePalette: Equatable, Sendable {
  let style: ColorSchemeStyle

  func token(for metric: MetricKind) -> ThemeColorToken {
    if metric == .neutral { return .gray }
    guard style == .multicolor else { return .blue }

    switch metric {
    case .cpu: return .blue
    case .memory: return .purple
    case .gpu: return .green
    case .battery: return .mint
    case .systemPower: return .orange
    case .temperature: return .redOrange
    case .fans: return .cyan
    case .neutral: return .gray
    }
  }
}

struct AppTheme: Equatable {
  let style: ColorSchemeStyle
  let palette: ThemePalette

  init(style: ColorSchemeStyle) {
    self.style = style
    palette = ThemePalette(style: style)
  }

  var primaryAccent: Color { .blue }

  func token(for metric: MetricKind) -> ThemeColorToken {
    palette.token(for: metric)
  }

  func color(for metric: MetricKind) -> Color {
    color(for: token(for: metric))
  }

  func color(for token: ThemeColorToken) -> Color {
    switch token {
    case .blue: return .blue
    case .purple: return .purple
    case .green: return .green
    case .mint: return .mint
    case .orange: return .orange
    case .redOrange: return Color(nsColor: .systemOrange)
    case .cyan: return .cyan
    case .gray: return Color(nsColor: .systemGray)
    }
  }
}

private struct AppThemeEnvironmentKey: EnvironmentKey {
  static let defaultValue = AppTheme(style: .duotone)
}

extension EnvironmentValues {
  var appTheme: AppTheme {
    get { self[AppThemeEnvironmentKey.self] }
    set { self[AppThemeEnvironmentKey.self] = newValue }
  }
}

@MainActor
final class ThemeController: ObservableObject {
  static let shared = ThemeController()
  static let defaultsKey = "interfaceColorScheme"

  @Published var style: ColorSchemeStyle {
    didSet { defaults.set(style.rawValue, forKey: key) }
  }

  private let defaults: UserDefaults
  private let key: String

  init(
    defaults: UserDefaults = .standard,
    key: String = ThemeController.defaultsKey
  ) {
    self.defaults = defaults
    self.key = key
    style = defaults.string(forKey: key).flatMap(ColorSchemeStyle.init(rawValue:)) ?? .duotone
  }

  var theme: AppTheme { AppTheme(style: style) }
}

extension View {
  func appTheme(_ theme: AppTheme) -> some View {
    environment(\.appTheme, theme)
      .tint(theme.primaryAccent)
  }
}

extension MetricDetailKind {
  var themeMetricKind: MetricKind {
    switch self {
    case .cpu: return .cpu
    case .memory: return .memory
    case .gpu: return .gpu
    case .battery: return .battery
    case .temperature: return .temperature
    case .fans: return .fans
    case .power: return .systemPower
    }
  }
}

extension MenuMetric {
  var themeMetricKind: MetricKind {
    switch self {
    case .cpu: return .cpu
    case .gpu: return .gpu
    case .memory: return .memory
    case .temperature: return .temperature
    case .battery: return .battery
    case .fans: return .fans
    case .systemPower, .adapterPower, .powerStatus: return .systemPower
    }
  }
}
