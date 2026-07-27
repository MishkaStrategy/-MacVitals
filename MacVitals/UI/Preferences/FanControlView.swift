import SwiftUI

struct FanControlSetupStatusView: View {
  @EnvironmentObject private var fanControl: FanControlClient

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      setupStep(
        number: 1,
        title: L10n.string("Signed application build"),
        detail: FanControlSigningIdentity.hasTeamIdentifier()
          ? L10n.string("The application has a valid Team ID.")
          : L10n.string("This test build is unsigned, so macOS blocks privileged fan control."),
        complete: FanControlSigningIdentity.hasTeamIdentifier(),
        symbol: "signature")

      setupStep(
        number: 2,
        title: L10n.string("Fan control helper"),
        detail: helperStepDetail,
        complete: helperInstalled,
        symbol: "wrench.and.screwdriver.fill")

      setupStep(
        number: 3,
        title: L10n.string("Administrator approval"),
        detail: approvalStepDetail,
        complete: fanControl.state.canControl,
        symbol: "checkmark.shield.fill")

      HStack(spacing: 9) {
        Button {
          fanControl.refreshStatus()
        } label: {
          Label(L10n.string("Check again"), systemImage: "arrow.clockwise")
        }
        .disabled(fanControl.operationInProgress)

        if FanControlSigningIdentity.hasTeamIdentifier() {
          Button {
            fanControl.prepareControl()
          } label: {
            Label(primaryActionTitle, systemImage: primaryActionSymbol)
          }
          .buttonStyle(.borderedProminent)
          .disabled(fanControl.operationInProgress || fanControl.state.canControl)
        }

        Spacer()

        stateBadge
      }
    }
    .onAppear { fanControl.refreshStatus() }
  }

  private func setupStep(
    number: Int,
    title: String,
    detail: String,
    complete: Bool,
    symbol: String
  ) -> some View {
    HStack(alignment: .top, spacing: 11) {
      ZStack {
        Circle()
          .fill(complete ? Color.green.opacity(0.17) : Color.secondary.opacity(0.12))
          .frame(width: 32, height: 32)
        Image(systemName: complete ? "checkmark" : symbol)
          .font(.caption.bold())
          .foregroundStyle(complete ? Color.green : Color.secondary)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(L10n.format("Step %d · %@", number, title))
          .font(.subheadline.weight(.semibold))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }

  private var helperInstalled: Bool {
    switch fanControl.state {
    case .connecting, .ready, .approvalRequired: return true
    default: return false
    }
  }

  private var helperStepDetail: String {
    switch fanControl.state {
    case .monitoringOnly:
      return L10n.string("A signed build is required before the helper can be registered.")
    case .notRegistered:
      return L10n.string("The helper is included but has not been registered with macOS yet.")
    case .approvalRequired:
      return L10n.string("The helper is registered and waiting for approval in Login Items.")
    case .connecting:
      return L10n.string("Connecting to the installed helper and running its self-check.")
    case .ready:
      return L10n.string("The helper is installed, connected, and ready.")
    case .unavailable(let message):
      return message
    }
  }

  private var approvalStepDetail: String {
    switch fanControl.state {
    case .ready: return L10n.string("Fan control is available for this signed build.")
    case .approvalRequired: return L10n.string("Open Login Items and allow the MacVitals helper.")
    case .monitoringOnly: return L10n.string("Approval cannot be requested from an unsigned build.")
    default: return L10n.string("Complete the previous step, then check the helper again.")
    }
  }

  private var primaryActionTitle: String {
    switch fanControl.state {
    case .approvalRequired: return L10n.string("Open Login Items")
    case .notRegistered: return L10n.string("Register helper")
    default: return L10n.string("Continue setup")
    }
  }

  private var primaryActionSymbol: String {
    fanControl.state == .approvalRequired ? "gearshape.fill" : "arrow.right.circle.fill"
  }

  private var stateBadge: some View {
    Label(
      fanControl.state.canControl ? L10n.string("Control ready") : L10n.string("Monitoring only"),
      systemImage: fanControl.state.canControl ? "checkmark.circle.fill" : "eye.fill")
      .font(.caption.bold())
      .foregroundStyle(fanControl.state.canControl ? Color.green : Color.secondary)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(.quaternary.opacity(0.45), in: Capsule())
  }
}

struct FanControlView: View {
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var fanControl: FanControlClient
  @State private var requestedRPM: [Int: Double] = [:]
  @State private var boostDurationMinutes = 15

  let compact: Bool

  init(compact: Bool = false) {
    self.compact = compact
  }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 8 : 12) {
      statusHeader

      Group {
        if compact {
          fanCards
        } else {
          ScrollView {
            fanCards
          }
          .frame(minHeight: 280)
        }
      }
      .accessibilityIdentifier("fanControlList")

      if !compact {
        Label(
          L10n.string(
            "Fan control is experimental. MacVitals only allows temporary cooling boosts and never permits a target below the current safety floor. macOS automatic control is restored when the lease expires or the helper disconnects."),
          systemImage: "shield.lefthalf.filled")
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
        Label(message, systemImage: "info.circle")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("fanControlLastMessage")
      }
    }
    .padding(compact ? 0 : 2)
    .onAppear { fanControl.refreshStatus() }
  }

  private var statusHeader: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        if !compact {
          Text("Fans").font(.title3.bold())
        }
        HStack(spacing: 6) {
          Circle()
            .fill(fanControl.state.canControl ? Color.green : Color.orange)
            .frame(width: 7, height: 7)
          Text(fanControl.state.message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("fanControlStatus")
        }
      }
      Spacer(minLength: 8)

      Picker(L10n.string("Boost duration"), selection: $boostDurationMinutes) {
        Text("5 min").tag(5)
        Text("15 min").tag(15)
        Text("30 min").tag(30)
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(width: compact ? 160 : 190)

      controlActivationButton
    }
  }

  @ViewBuilder
  private var fanCards: some View {
    if let fans = coordinator.snapshot.fans.value?.fans, !fans.isEmpty {
      VStack(spacing: 8) {
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
      Button {
        fanControl.prepareControl()
      } label: {
        Label(L10n.string("Monitoring only"), systemImage: "lock.fill")
      }
      .accessibilityIdentifier("enableFanControlButton")
    case .notRegistered:
      Button("Enable Control") { fanControl.requestApproval() }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("enableFanControlButton")
    case .approvalRequired:
      Button("Review Approval") { fanControl.openApprovalSettings() }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("reviewFanControlApprovalButton")
    case .connecting:
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel("Fan control helper")
    case .ready:
      Button("Use System Automatic") { fanControl.setAllAutomatic() }
        .disabled(fanControl.operationInProgress)
        .accessibilityIdentifier("restoreAllFansAuto")
    case .unavailable:
      Button {
        fanControl.refreshStatus()
      } label: {
        Label(L10n.string("Retry"), systemImage: "arrow.clockwise")
      }
      .disabled(fanControl.operationInProgress)
    }
  }

  private func fanCard(_ fan: FanReading) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Label(L10n.format("Fan %d", fan.index + 1), systemImage: "fan.fill")
          .font(.headline)
        Spacer()
        Text(MetricNumberFormatter.rpm(fan.currentRPM) ?? L10n.string("Collecting data"))
          .font(.headline.monospacedDigit())
      }

      HStack(spacing: 16) {
        LabeledContent("Target speed", value: MetricNumberFormatter.rpm(fan.targetRPM) ?? "—")
        LabeledContent("Mode", value: fan.mode.displayName)
        if let minimum = MetricNumberFormatter.rpm(fan.minimumRPM),
          let maximum = MetricNumberFormatter.rpm(fan.maximumRPM)
        {
          LabeledContent(L10n.string("Safe range"), value: "\(minimum) – \(maximum)")
        }
      }
      .font(.caption)

      if let range = FanControlSafetyPolicy.safeBoostRange(for: fan) {
        let binding = rpmBinding(for: fan, range: range)
        HStack(spacing: 8) {
          Slider(value: binding, in: range, step: 100)
            .frame(maxWidth: compact ? 270 : 360)
            .accessibilityIdentifier("fanBoostSlider.\(fan.index)")
          Text(MetricNumberFormatter.rpm(binding.wrappedValue) ?? "—")
            .font(.caption.monospacedDigit())
            .frame(width: 78, alignment: .trailing)
        }

        HStack(spacing: 8) {
          Button {
            if fanControl.state.canControl {
              fanControl.setBoost(
                fan: fan,
                requestedRPM: binding.wrappedValue,
                leaseSeconds: TimeInterval(boostDurationMinutes * 60))
            } else {
              fanControl.prepareControl()
            }
          } label: {
            Label(
              L10n.format("Boost for %d min", boostDurationMinutes),
              systemImage: "snowflake")
          }
          .buttonStyle(.borderedProminent)
          .disabled(fanControl.operationInProgress)
          .accessibilityIdentifier("applyFanBoost.\(fan.index)")

          Button {
            if fanControl.state.canControl {
              fanControl.setAutomatic(fanIndex: fan.index)
            } else {
              fanControl.prepareControl()
            }
          } label: {
            Label(L10n.string("Automatic"), systemImage: "arrow.triangle.2.circlepath")
          }
          .disabled(fanControl.operationInProgress)
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
    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11))
    .overlay(
      RoundedRectangle(cornerRadius: 11)
        .stroke(.quaternary.opacity(0.35), lineWidth: 1))
    .accessibilityIdentifier("fanSection.\(fan.index)")
  }

  private var controlAvailabilityNote: String? {
    switch fanControl.state {
    case .monitoringOnly:
      return L10n.string("RPM monitoring works in this build. Actual control requires a separately signed MacVitals build and administrator approval.")
    case .notRegistered:
      return L10n.string("Register the included helper to enable temporary cooling control.")
    case .approvalRequired:
      return L10n.string("Approve MacVitals in System Settings › General › Login Items, then press Check again.")
    case .connecting:
      return L10n.string("The signed helper is being verified.")
    case .ready:
      return L10n.string("Temporary boosts and automatic restoration are available.")
    case .unavailable(let message):
      return message
    }
  }

  private func rpmBinding(
    for fan: FanReading,
    range: ClosedRange<Double>
  ) -> Binding<Double> {
    Binding(
      get: {
        if let existing = requestedRPM[fan.index] {
          return min(range.upperBound, max(range.lowerBound, existing))
        }
        return FanControlSafetyPolicy.defaultBoostRPM(for: fan, range: range)
      },
      set: { requestedRPM[fan.index] = min(range.upperBound, max(range.lowerBound, $0)) }
    )
  }
}
