import AppKit
import SwiftUI

@MainActor
final class StatusBarPetSettingsWindowController: NSWindowController, NSWindowDelegate {
  private let settings: StatusBarPetSettingsStore

  init(settings: StatusBarPetSettingsStore) {
    self.settings = settings
    let rootView = StatusBarPetSettingsView(settings: settings)
    let hostingController = NSHostingController(rootView: rootView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = StatusBarPetL10n.string("Electric Dragon")
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.setContentSize(NSSize(width: 470, height: 520))
    window.minSize = NSSize(width: 440, height: 480)
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
    window.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func present() {
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowShouldClose(_: NSWindow) -> Bool {
    window?.orderOut(nil)
    return false
  }
}

private struct StatusBarPetSettingsView: View {
  @ObservedObject var settings: StatusBarPetSettingsStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        preview
        behaviorCard
        appearanceCard
        footer
      }
      .padding(20)
    }
    .frame(minWidth: 440, minHeight: 480)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "bolt.heart.fill")
        .font(.title2.bold())
        .foregroundStyle(.cyan)
        .frame(width: 38, height: 38)
        .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

      VStack(alignment: .leading, spacing: 2) {
        Text(StatusBarPetL10n.string("Electric Dragon"))
          .font(.title3.bold())
        Text(StatusBarPetL10n.string("A tiny friendly dragon that lives only on the hardware notch."))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Toggle("", isOn: enabledBinding)
        .labelsHidden()
        .accessibilityLabel(StatusBarPetL10n.string("Enable electric dragon"))
        .accessibilityIdentifier("statusBarPetEnabledToggle")
    }
  }

  private var preview: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(StatusBarPetL10n.string("Preview"))
        .font(.headline)

      TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
        let time = timeline.date.timeIntervalSinceReferenceDate
        GeometryReader { proxy in
          let notchWidth = min(212.0, proxy.size.width * 0.58)
          let notchLeft = (proxy.size.width - notchWidth) / 2
          let travel = notchWidth + 28
          let petX = notchLeft - 14 + (sin(time * 0.72) + 1) * travel / 2
          let petY = petX < notchLeft || petX > notchLeft + notchWidth ? 21.0 : 47.0

          ZStack(alignment: .topLeading) {
            LinearGradient(
              colors: [Color.indigo.opacity(0.72), Color.blue.opacity(0.34)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(.black)
              .frame(width: notchWidth, height: 40)
              .position(x: proxy.size.width / 2, y: 17)

            NotchDragonPreviewGlyph(
              time: time,
              sparkIntensity: settings.configuration.sparkIntensity)
              .frame(
                width: settings.configuration.size.width,
                height: settings.configuration.size.height)
              .position(x: petX, y: petY)
          }
        }
      }
      .frame(height: 82)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
  }

  private var behaviorCard: some View {
    settingsCard(
      title: StatusBarPetL10n.string("Behavior"),
      symbol: "sparkles") {
        VStack(spacing: 12) {
          toggleRow(
            title: StatusBarPetL10n.string("Move around the notch"),
            detail: StatusBarPetL10n.string("The dragon wraps around the notch and never walks across the menu bar."),
            isOn: roamBinding)
          Divider()
          toggleRow(
            title: StatusBarPetL10n.string("Play with the cursor near the notch"),
            detail: StatusBarPetL10n.string("The dragon reacts only when the pointer is directly beside the notch."),
            isOn: interactionBinding)
          Divider()
          toggleRow(
            title: StatusBarPetL10n.string("Respect Reduce Motion"),
            detail: StatusBarPetL10n.string("Pause notch movement when macOS Reduce Motion is enabled."),
            isOn: reducedMotionBinding)

          Divider()

          VStack(alignment: .leading, spacing: 7) {
            HStack {
              Text(StatusBarPetL10n.string("Movement speed"))
              Spacer()
              Text(String(format: "%.1fx", settings.configuration.movementSpeed))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: speedBinding, in: 0.45...1.8, step: 0.05)
              .accessibilityIdentifier("statusBarPetSpeedSlider")
          }
        }
      }
  }

  private var appearanceCard: some View {
    settingsCard(
      title: StatusBarPetL10n.string("Appearance"),
      symbol: "face.smiling") {
        VStack(alignment: .leading, spacing: 12) {
          Picker(StatusBarPetL10n.string("Dragon size"), selection: sizeBinding) {
            ForEach(StatusBarPetSize.allCases) { size in
              Text(size.displayName).tag(size)
            }
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("statusBarPetSizePicker")

          Divider()

          VStack(alignment: .leading, spacing: 7) {
            HStack {
              Text(StatusBarPetL10n.string("Electric sparks"))
              Spacer()
              Text("\(Int(settings.configuration.sparkIntensity * 100))%")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Slider(value: sparksBinding, in: 0...1, step: 0.05)
              .accessibilityIdentifier("statusBarPetSparkSlider")
          }
        }
      }
  }

  private var footer: some View {
    HStack {
      Label(
        StatusBarPetL10n.string("Shown only on a display with a hardware notch; mouse clicks pass through."),
        systemImage: "macbook")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Button(StatusBarPetL10n.string("Restore Defaults")) {
        settings.reset()
      }
      .accessibilityIdentifier("statusBarPetRestoreDefaultsButton")
    }
  }

  private func settingsCard<Content: View>(
    title: String,
    symbol: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: symbol)
        .font(.headline)
      content()
    }
    .padding(14)
    .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.primary.opacity(0.07), lineWidth: 1))
  }

  private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline.weight(.semibold))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 10)
      Toggle("", isOn: isOn)
        .labelsHidden()
    }
  }

  private var enabledBinding: Binding<Bool> {
    Binding(
      get: { settings.configuration.isEnabled },
      set: { settings.configuration.isEnabled = $0 })
  }

  private var roamBinding: Binding<Bool> {
    Binding(
      get: { settings.configuration.roamEnabled },
      set: { settings.configuration.roamEnabled = $0 })
  }

  private var interactionBinding: Binding<Bool> {
    Binding(
      get: { settings.configuration.cursorInteractionEnabled },
      set: { settings.configuration.cursorInteractionEnabled = $0 })
  }

  private var reducedMotionBinding: Binding<Bool> {
    Binding(
      get: { settings.configuration.respectReducedMotion },
      set: { settings.configuration.respectReducedMotion = $0 })
  }

  private var speedBinding: Binding<Double> {
    Binding(
      get: { settings.configuration.movementSpeed },
      set: { settings.configuration.movementSpeed = $0 })
  }

  private var sparksBinding: Binding<Double> {
    Binding(
      get: { settings.configuration.sparkIntensity },
      set: { settings.configuration.sparkIntensity = $0 })
  }

  private var sizeBinding: Binding<StatusBarPetSize> {
    Binding(
      get: { settings.configuration.size },
      set: { settings.configuration.size = $0 })
  }
}

private struct NotchDragonPreviewGlyph: View {
  let time: TimeInterval
  let sparkIntensity: Double

  var body: some View {
    ZStack {
      Circle()
        .fill(Color.cyan.opacity(0.12 + sparkIntensity * 0.12))
        .scaleEffect(1 + sin(time * 3.4) * 0.05)

      Capsule()
        .fill(
          LinearGradient(
            colors: [.indigo, .blue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing))
        .frame(width: 19, height: 13)
        .rotationEffect(.degrees(sin(time * 4) * 3))

      Circle()
        .fill(Color.blue)
        .frame(width: 14, height: 14)
        .offset(x: -7, y: -3)

      HStack(spacing: 3) {
        Circle().fill(.white).frame(width: 3.5, height: 4.5)
        Circle().fill(.white).frame(width: 3.5, height: 4.5)
      }
      .offset(x: -7, y: -4)

      Image(systemName: "bolt.fill")
        .font(.system(size: 6, weight: .bold))
        .foregroundStyle(.cyan)
        .offset(x: 9, y: -7)
    }
  }
}
