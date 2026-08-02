import SwiftUI

extension Notification.Name {
  static let openStatusBarHUDPreferences = Notification.Name("openStatusBarHUDPreferences")
}

@MainActor
struct CompactNotchHUDPreferencesView: View {
  @EnvironmentObject private var coordinator: MetricsCoordinator
  @EnvironmentObject private var settings: SettingsStore

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 12) {
        previewCard
        sensorCard
        appearanceCard
        thresholdsCard
        displayCard
        resetRow
      }
      .padding(18)
    }
    .accessibilityIdentifier("notchHUDIntegratedSettings")
  }

  private var previewCard: some View {
    CompactIndicatorCard {
      HStack(spacing: 10) {
        Label(L10n.string("Live preview"), systemImage: "eye.fill")
          .font(.headline)
        Spacer()
        Toggle(L10n.string("Enabled"), isOn: $settings.showAroundStatusBar)
          .toggleStyle(.switch)
          .accessibilityIdentifier("notchHUDEnabledToggle")
      }

      ZStack {
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.black.opacity(0.9))
        NotchHUDIndicatorContentView(
          snapshot: coordinator.snapshot,
          configuration: settings.notchHUDConfiguration,
          safeAreaTop: 34
        )
        .frame(
          width: min(
            500,
            NotchHUDLayout.preferredPanelWidth(
              configuration: settings.notchHUDConfiguration)),
          height: 70)
      }
      .frame(height: 82)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.white.opacity(0.1), lineWidth: 1))
      .accessibilityIdentifier("notchHUDLivePreview")
    }
  }

  private var sensorCard: some View {
    CompactIndicatorCard {
      Label(L10n.string("Displayed sensor"), systemImage: "sensor.fill")
        .font(.headline)

      HStack(spacing: 14) {
        VStack(alignment: .leading, spacing: 3) {
          Text(L10n.string("Display one sensor"))
            .font(.subheadline.weight(.semibold))
          Text(L10n.string("The contour fill and value use this live sensor."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Picker(L10n.string("Display one sensor"), selection: metricBinding) {
          ForEach(MenuMetric.notchIndicatorMetrics) { metric in
            Label(metric.displayName, systemImage: metric.defaultSymbol)
              .tag(metric)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 210)
        .accessibilityIdentifier("notchIndicatorMetricPicker")
      }
    }
  }

  private var appearanceCard: some View {
    CompactIndicatorCard {
      Label(L10n.string("Indicator appearance"), systemImage: "scribble.variable")
        .font(.headline)

      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 11) {
        GridRow {
          compactLabel(L10n.string("Value text"))
          HStack(spacing: 16) {
            Toggle(
              L10n.string("Show current value"),
              isOn: configurationBinding(\.showValueText)
            )
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("notchIndicatorShowValueToggle")
            Toggle(
              L10n.string("Show sensor name"),
              isOn: configurationBinding(\.showSensorName)
            )
            .toggleStyle(.checkbox)
            .disabled(!settings.notchHUDConfiguration.showValueText)
          }
        }

        GridRow {
          compactLabel(L10n.string("Color mode"))
          HStack(spacing: 10) {
            Picker(
              L10n.string("Color mode"),
              selection: configurationBinding(\.colorMode)
            ) {
              ForEach(NotchIndicatorColorMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
              }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if settings.notchHUDConfiguration.colorMode == .custom {
              Picker(
                L10n.string("Custom color"),
                selection: configurationBinding(\.accent)
              ) {
                ForEach(NotchIndicatorAccent.allCases) { accent in
                  Text(accent.displayName).tag(accent)
                }
              }
              .labelsHidden()
              .pickerStyle(.menu)
              .frame(width: 120)
            }
          }
        }

        GridRow {
          compactLabel(L10n.string("Line thickness"))
          valueSlider(
            value: configurationBinding(\.lineThickness),
            range: 1...6,
            step: 0.5,
            suffix: "pt",
            identifier: "notchIndicatorLineThicknessSlider")
        }

        GridRow {
          compactLabel(L10n.string("Contour width"))
          valueSlider(
            value: configurationBinding(\.horizontalExtension),
            range: 36...180,
            step: 4,
            suffix: "pt",
            identifier: "notchIndicatorContourWidthSlider")
        }

        GridRow {
          compactLabel(L10n.string("Inactive track"))
          percentageSlider(
            value: configurationBinding(\.trackOpacity),
            range: 0.05...0.55,
            identifier: "notchIndicatorTrackOpacitySlider")
        }

        GridRow {
          compactLabel(L10n.string("Glow"))
          percentageSlider(
            value: configurationBinding(\.glowIntensity),
            range: 0...1,
            identifier: "notchIndicatorGlowSlider")
        }
      }

      Divider()

      Toggle(
        L10n.string("Animate value changes"),
        isOn: configurationBinding(\.animateChanges))
        .toggleStyle(.checkbox)
    }
  }

  private var thresholdsCard: some View {
    CompactIndicatorCard {
      Label(
        L10n.string("Threshold colors"),
        systemImage: "gauge.with.dots.needle.67percent"
      )
      .font(.headline)

      HStack(spacing: 14) {
        VStack(alignment: .leading, spacing: 3) {
          Text(L10n.string("Warning and critical states"))
            .font(.subheadline.weight(.semibold))
          Text(thresholdDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()

        thresholdField(
          title: L10n.string("Warning"),
          value: configurationBinding(\.warningThreshold),
          identifier: "notchIndicatorWarningField")
        thresholdField(
          title: L10n.string("Critical"),
          value: configurationBinding(\.criticalThreshold),
          identifier: "notchIndicatorCriticalField")
      }
    }
  }

  private var displayCard: some View {
    CompactIndicatorCard {
      Toggle(
        isOn: configurationBinding(\.showOnDisplaysWithoutNotch)
      ) {
        Label(
          L10n.string("Show a simulated contour on displays without a notch"),
          systemImage: "display.2"
        )
        .font(.subheadline.weight(.semibold))
      }
      .toggleStyle(.switch)
    }
  }

  private var resetRow: some View {
    HStack {
      Text(L10n.string("Only one sensor is shown around the notch at a time."))
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Button(L10n.string("Restore Indicator Defaults")) {
        settings.resetNotchHUDConfiguration()
      }
      .accessibilityIdentifier("restoreNotchHUDDefaultsButton")
    }
    .padding(.horizontal, 2)
  }

  private var metricBinding: Binding<MenuMetric> {
    Binding(
      get: { settings.notchHUDConfiguration.metric },
      set: { settings.setNotchHUDMetric($0, side: nil) })
  }

  private var thresholdDescription: String {
    settings.notchHUDConfiguration.metric.notchIndicatorLowerIsWorse
      ? L10n.string("Lower values become warning and critical colors.")
      : L10n.string("Higher values become warning and critical colors.")
  }

  private func configurationBinding<Value>(
    _ keyPath: WritableKeyPath<NotchHUDConfiguration, Value>
  ) -> Binding<Value> {
    Binding(
      get: { settings.notchHUDConfiguration[keyPath: keyPath] },
      set: { newValue in
        var configuration = settings.notchHUDConfiguration
        configuration[keyPath: keyPath] = newValue
        settings.notchHUDConfiguration = configuration
      })
  }

  private func compactLabel(_ title: String) -> some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .frame(width: 124, alignment: .leading)
  }

  private func valueSlider(
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double,
    suffix: String,
    identifier: String
  ) -> some View {
    HStack(spacing: 9) {
      Slider(value: value, in: range, step: step)
        .accessibilityIdentifier(identifier)
      Text("\(value.wrappedValue, specifier: "%.1f") \(suffix)")
        .font(.caption.monospacedDigit())
        .frame(width: 62, alignment: .trailing)
    }
  }

  private func percentageSlider(
    value: Binding<Double>,
    range: ClosedRange<Double>,
    identifier: String
  ) -> some View {
    HStack(spacing: 9) {
      Slider(value: value, in: range, step: 0.05)
        .accessibilityIdentifier(identifier)
      Text("\(Int(value.wrappedValue * 100))%")
        .font(.caption.monospacedDigit())
        .frame(width: 42, alignment: .trailing)
    }
  }

  private func thresholdField(
    title: String,
    value: Binding<Double>,
    identifier: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
        .textFieldStyle(.roundedBorder)
        .frame(width: 92)
        .accessibilityIdentifier(identifier)
    }
  }
}

private struct CompactIndicatorCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      content
    }
    .padding(13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 11))
    .overlay(
      RoundedRectangle(cornerRadius: 11)
        .stroke(.quaternary.opacity(0.38), lineWidth: 1))
  }
}
