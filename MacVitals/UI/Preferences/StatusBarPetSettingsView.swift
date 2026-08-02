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
      Image(systemName: "bolt.fill")
        .font(.title2.bold())
        .foregroundStyle(.cyan)
        .frame(width: 38, height: 38)
        .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

      VStack(alignment: .leading, spacing: 2) {
        Text(StatusBarPetL10n.string("Electric Dragon"))
          .font(.title3.bold())
        Text(StatusBarPetL10n.string("A tiny animated companion that lives beside MacVitals."))
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
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.black.opacity(0.86))
        HStack(spacing: 10) {
          Label("MacVitals", systemImage: "waveform.path.ecg")
            .font(.system(size: 13, weight: .semibold))
          Divider().frame(height: 18)
          Text("CPU 18%")
          Text("52°C")
          Text("74%")
            .foregroundStyle(.green)
          Spacer()
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)

        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
          let time = timeline.date.timeIntervalSinceReferenceDate
          previewDragon(time: time)
        }
      }
      .frame(height: 64)
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
  }

  private func previewDragon(time: TimeInterval) -> some View {
    let width = settings.configuration.size.width
    let height = settings.configuration.size.height
    let travel = 250.0
    let position = 82 + (sin(time * 0.7) + 1) * travel / 2
    return StatusBarPetPreviewDragon(
      configuration: settings.configuration,
      time: time)
      .frame(width: width, height: height)
      .position(x: position, y: 17 + height / 2)
  }

  private var behaviorCard: some View {
    settingsCard(
      title: StatusBarPetL10n.string("Behavior"),
      symbol: "figure.walk.motion") {
        VStack(spacing: 12) {
          toggleRow(
            title: StatusBarPetL10n.string("Walk along the status bar"),
            detail: StatusBarPetL10n.string("The dragon occasionally explores near the MacVitals item."),
            isOn: roamBinding)
          Divider()
          toggleRow(
            title: StatusBarPetL10n.string("Play with the cursor"),
            detail: StatusBarPetL10n.string("Hover nearby and the dragon will chase and spark at the pointer."),
            isOn: interactionBinding)
          Divider()
          toggleRow(
            title: StatusBarPetL10n.string("Respect Reduce Motion"),
            detail: StatusBarPetL10n.string("Stop roaming when macOS Reduce Motion is enabled."),
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
      symbol: "sparkles") {
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
        StatusBarPetL10n.string("The overlay never intercepts mouse clicks."),
        systemImage: "cursorarrow.rays")
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

private struct StatusBarPetPreviewDragon: View {
  let configuration: StatusBarPetConfiguration
  let time: TimeInterval

  var body: some View {
    ZStack {
      Circle()
        .fill(
          RadialGradient(
            colors: [.cyan.opacity(0.46), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 24))
        .scaleEffect(1 + sin(time * 4) * 0.06)

      Image(systemName: "bolt.fill")
        .font(.system(size: configuration.size.height * 0.66, weight: .black))
        .foregroundStyle(
          LinearGradient(
            colors: [.indigo, .blue, .cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing))
        .rotationEffect(.degrees(-18 + sin(time * 5) * 5))
        .shadow(color: .cyan.opacity(configuration.sparkIntensity), radius: 3)
    }
  }
}
