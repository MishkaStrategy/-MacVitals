import Foundation

nonisolated enum ExternalPowerState: Equatable, Sendable {
  case connected
  case disconnected
  case unknown
}

nonisolated enum ExternalPowerResolver {
  static func resolve(
    battery: BatteryStats?,
    batteryAvailability: MetricAvailability,
    adapter: AdapterStats?,
    adapterAvailability: MetricAvailability
  ) -> ExternalPowerState {
    if let battery {
      if battery.present {
        guard batteryAvailability == .available else { return .unknown }
        return battery.externalPowerConnected ? .connected : .disconnected
      }
      guard batteryAvailability == .unsupported else { return .unknown }
      return .connected
    }

    guard adapterAvailability == .available, let adapter else { return .unknown }
    return adapter.connected ? .connected : .disconnected
  }
}

nonisolated enum UnknownExternalPowerAssessment {
  static func make(for state: ExternalPowerState) -> PowerAssessment? {
    guard state == .unknown else { return nil }
    return PowerAssessment(
      status: .unknown,
      confidence: 0,
      batteryPowerWatts: nil,
      estimatedSystemPowerWatts: nil,
      powerBalanceWatts: nil,
      explanation: L10n.string("Power state cannot be determined"))
  }
}
