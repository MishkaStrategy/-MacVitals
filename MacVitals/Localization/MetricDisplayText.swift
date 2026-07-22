import Foundation

extension MetricAvailability {
  var displayName: String {
    switch self {
    case .available: return L10n.string("Available")
    case .temporarilyUnavailable: return L10n.string("Temporarily unavailable")
    case .unsupported: return L10n.string("Unsupported")
    case .permissionRequired: return L10n.string("Permission required")
    case .providerError: return L10n.string("Provider error")
    case .stale: return L10n.string("Stale")
    case .estimated: return L10n.string("Estimated")
    }
  }
}

extension MetricSource {
  var displayName: String {
    switch self {
    case .machHostStatistics: return L10n.string("Mach host statistics")
    case .iokitPowerSources: return L10n.string("IOKit power sources")
    case .iokitRegistry: return L10n.string("IOKit registry")
    case .metal: return L10n.string("Metal")
    case .derivedPowerModel: return L10n.string("Derived power model")
    case .unavailable: return L10n.string("Unavailable")
    }
  }
}
