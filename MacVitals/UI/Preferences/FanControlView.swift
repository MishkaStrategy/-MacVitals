import SwiftUI

struct FanControlView: View {
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var fanControl: FanControlClient
  @State private var requestedRPM: [Int: Double] = [:]

  let compact: Bool

  init(compact: Bool = false) {
    self.compact = compact
  }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 8 : 12) {
      statusHeader

      if compact {
        ScrollView {
          fanCards
        }
        .frame(maxHeight: 245)
      } else {
        ScrollView {
          fanCards
        }
        .frame(minHeight: 280)
      }

      if !compact {
        Text(
          "Fan control is experimental. MacVitals only allows temporary cooling boosts and never permits a target below the current safety floor. macOS automatic control is restored when the lease expires or the helper disconnects."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("fanControlSafetyNotice")
      }

      if let note = controlAvailabilityNote {
        Label(note, systemImage: fanControl.state.canControl ? "checkmark.shield" : "lock.shield")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let message = fanControl.lastMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("fanControlLastMessage")
      }
    }
    .padding(compact ? 0 : 16)
    .onAppear { fanControl.refreshStatus() }
  }

  private var statusHeader: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        if !compact {
          Text("Fans").font(.title2.bold())
        }
        Text(fanControl.state.message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("fanControlStatus")
      }
      Spacer(minLength: 8)
      controlActivationButton
    }
  }

  @ViewBuilder
  private var fanCards: some View {
    if let fans = coordinator.snapshot.fans.value?.fans, !fans.isEmpty {
      LazyVStack(spacing: 8) {
        ForEach(fans) { fan in
          fanCard(fan)
        }
      }
      .padding(.vertical, 2)
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

  @ViewBuilder
  private var controlActivationButton: some View {
    switch fanControl.state {
    case .monitoringOnly:
      Label("Signed build required", systemImage: "lock.fill")
        .font(.caption.bold())
        .foregroundStyle(.secondary)
    case .notRegistered:
      Button("Enable Control") { fanControl.requestApproval() }
        .accessibilityIdentifier("enableFanControlButton")
    case .approvalRequired:
      Button("Review Approval") { fanControl.openApprovalSettings() }
        .accessibilityIdentifier("reviewFanControlApprovalButton")
    case .connecting:
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel("Connecting to fan control helper")
    case .ready:
      Button("All Automatic") { fanControl.setAllAutomatic() }
        .disabled(fanControl.operationInProgress)
        .accessibilityIdentifier("restoreAllFansAuto")
    case .unavailable:
      Button("Retry") { fanControl.refreshStatus() }
        .disabled(fanControl.operationInProgress)
    }
  }

  private func fanCard(_ fan: FanReading) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(L10n.format("Fan %d", fan.index + 1))
          .font(.headline)
        Spacer()
        Text(MetricNumberFormatter.rpm(fan.currentRPM) ?? "—")
          .font(.headline.monospacedDigit())
      }

      HStack(spacing: 16) {
        LabeledContent("Target", value: MetricNumberFormatter.rpm(fan.targetRPM) ?? "—")
        LabeledContent("Mode", value: fan.mode.displayName)
      }
      .font(.caption)

      if let range = FanControlSafetyPolicy.safeBoostRange(for: fan) {
        let binding = rpmBinding(for: fan, range: range)
        HStack(spacing: 8) {
          Slider(value: binding, in: range, step: 100)
            .frame(maxWidth: compact ? 260 : 360)
            .accessibilityIdentifier("fanBoostSlider.\(fan.index)")
          Text(MetricNumberFormatter.rpm(binding.wrappedValue) ?? "—")
            .font(.caption.monospacedDigit())
            .frame(width: 76, alignment: .trailing)
        }

        HStack(spacing: 8) {
          Button("Boost 15 min") {
            fanControl.setBoost(fan: fan, requestedRPM: binding.wrappedValue)
          }
          .disabled(!fanControl.state.canControl || fanControl.operationInProgress)
          .accessibilityIdentifier("applyFanBoost.\(fan.index)")

          Button("Automatic") {
            fanControl.setAutomatic(fanIndex: fan.index)
          }
          .disabled(!fanControl.state.canControl || fanControl.operationInProgress)
          .accessibilityIdentifier("restoreFanAuto.\(fan.index)")

          if fanControl.operationInProgress {
            ProgressView().controlSize(.small)
          }
        }
      } else {
        Text("This fan does not expose a safe controllable RPM range.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityIdentifier("fanSection.\(fan.index)")
  }

  private var controlAvailabilityNote: String? {
    switch fanControl.state {
    case .monitoringOnly:
      return L10n.string(
        "This unsigned test build can monitor fan speed, but macOS will not allow it to control the fans. Control requires a separately signed helper and administrator approval.")
    case .notRegistered:
      return L10n.string("Enable the helper, then approve it in System Settings when macOS asks.")
    case .approvalRequired:
      return L10n.string("Approve MacVitals in System Settings › General › Login Items.")
    case .connecting:
      return L10n.string("Checking the privileged helper before enabling controls.")
    case .ready:
      return L10n.string("Temporary boosts are active only for the selected lease and then return to Automatic.")
    case .unavailable:
      return L10n.string("The helper did not respond. Retry or restore all fans to Automatic from a signed build.")
    }
  }

  private func rpmBinding(for fan: FanReading, range: ClosedRange<Double>) -> Binding<Double> {
    Binding(
      get: {
        let initial = fan.targetRPM ?? max(range.lowerBound, range.upperBound * 0.75)
        return requestedRPM[fan.index] ?? min(range.upperBound, max(range.lowerBound, initial))
      },
      set: { requestedRPM[fan.index] = min(range.upperBound, max(range.lowerBound, $0)) })
  }
}
