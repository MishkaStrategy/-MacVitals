import SwiftUI

struct FanControlView: View {
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var fanControl: FanControlClient
  @State private var requestedRPM: [Int: Double] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Fans").font(.title2.bold())
          Text(fanControl.state.message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("fanControlStatus")
        }
        Spacer()
        controlActivationButton
      }

      List {
        if let fans = coordinator.snapshot.fans.value?.fans, !fans.isEmpty {
          ForEach(fans) { fan in
            fanSection(fan)
          }
        } else {
          VStack(spacing: 8) {
            Image(systemName: "fan").font(.title2)
            Text("Fan data unavailable").font(.headline)
            Text(coordinator.snapshot.fans.message ?? L10n.string("Collecting data"))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding()
        }
      }
      .accessibilityIdentifier("fanControlList")

      Text(
        "Fan control is experimental. MacVitals only allows temporary cooling boosts and never permits a target below the current safety floor. macOS automatic control is restored when the lease expires or the helper disconnects."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("fanControlSafetyNotice")

      if let message = fanControl.lastMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("fanControlLastMessage")
      }
    }
    .padding()
    .onAppear { fanControl.refreshStatus() }
  }

  @ViewBuilder
  private var controlActivationButton: some View {
    switch fanControl.state {
    case .notRegistered:
      Button("Enable Control") { fanControl.requestApproval() }
        .accessibilityIdentifier("enableFanControlButton")
    case .approvalRequired:
      Button("Review Approval") { fanControl.openApprovalSettings() }
        .accessibilityIdentifier("reviewFanControlApprovalButton")
    case .ready:
      Label("Ready", systemImage: "checkmark.circle")
        .foregroundStyle(.secondary)
    case .monitoringOnly, .unavailable:
      EmptyView()
    }
  }

  @ViewBuilder
  private func fanSection(_ fan: FanReading) -> some View {
    Section(L10n.format("Fan %d", fan.index + 1)) {
      LabeledContent("Current speed", value: MetricNumberFormatter.rpm(fan.currentRPM) ?? "—")
      LabeledContent("Target speed", value: MetricNumberFormatter.rpm(fan.targetRPM) ?? "—")
      LabeledContent("Mode", value: fan.mode.displayName)
      LabeledContent("Hardware range", value: hardwareRange(fan))

      if let range = FanControlSafetyPolicy.safeBoostRange(for: fan) {
        let binding = rpmBinding(for: fan, range: range)
        LabeledContent("Cooling boost") {
          HStack {
            Slider(value: binding, in: range, step: 100)
              .frame(width: 240)
              .accessibilityIdentifier("fanBoostSlider.\(fan.index)")
            Text(MetricNumberFormatter.rpm(binding.wrappedValue) ?? "—")
              .monospacedDigit()
              .frame(width: 86, alignment: .trailing)
          }
        }

        HStack {
          Button("Apply 15-minute Boost") {
            fanControl.setBoost(fan: fan, requestedRPM: binding.wrappedValue)
          }
          .disabled(!fanControl.state.canControl || fanControl.operationInProgress)
          .accessibilityIdentifier("applyFanBoost.\(fan.index)")

          Button("Use System Automatic") {
            fanControl.setAutomatic(fanIndex: fan.index)
          }
          .disabled(!fanControl.state.canControl || fanControl.operationInProgress)
          .accessibilityIdentifier("restoreFanAuto.\(fan.index)")
        }
      } else {
        Text("This fan does not expose a safe controllable RPM range.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityIdentifier("fanSection.\(fan.index)")
  }

  private func rpmBinding(for fan: FanReading, range: ClosedRange<Double>) -> Binding<Double> {
    Binding(
      get: {
        let initial = fan.targetRPM ?? max(range.lowerBound, range.upperBound * 0.75)
        return requestedRPM[fan.index] ?? min(range.upperBound, max(range.lowerBound, initial))
      },
      set: { requestedRPM[fan.index] = min(range.upperBound, max(range.lowerBound, $0)) })
  }

  private func hardwareRange(_ fan: FanReading) -> String {
    guard let minimum = MetricNumberFormatter.rpm(fan.minimumRPM),
      let maximum = MetricNumberFormatter.rpm(fan.maximumRPM)
    else { return "—" }
    return "\(minimum) – \(maximum)"
  }
}
