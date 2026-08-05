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
      Label(L10n.string("Displayed sensors"), systemImage: "sensor.fill")
        .font(.headline)

      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 11) {
        GridRow {
          compactLabel(L10n.string("Indicator count"))
          Picker(
            L10n.string("Indicator count"),
            selection: indicatorCountBinding
          ) {
            ForEach(NotchIndicatorCount.allCases) { count in
              Text(count.displayName).tag(count)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .accessibilityIdentifier("notchIndicatorCountPicker")
        }

        GridRow {
          compactLabel(L10n.string("Indicator 1 (left)"))
          metricPicker(
            selection: primaryMetricBinding,
            metrics: MenuMetric.notchIndicatorMetrics,
            identifier: "notchIndicatorPrimaryMetricPicker")
        }

        if settings.notchHUDConfiguration.indicatorCount == .two {
          GridRow {
            compactLabel(L10n.string("Indicator 2 (right)"))
            metricPicker(
              selection: secondaryMetricBinding,
              metrics: availableSecondaryMetrics,
              identifier: "notchIndicatorSecondaryMetricPicker")
          }
        }
      }

      Text(indicatorCountDescription)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var appearanceCard: some View {
    CompactIndicatorCard {
      Label(L10n.string("Indicator appearance"), systemImage: "scribble.variable")
        .font(.headline)

      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 11) {
        GridRow {
          compactLabel(L10n.string("Lower labels"))
          HStack(spacing: 16) {
            Toggle(
              L10n.string("Show labels below the contour"),
              isOn: configurationBinding(\.showValueText)
            )
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("notchIndicatorShowBottomLabelsToggle")

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

      thresholdRow(
        title: L10n.string("Indicator 1"),
        metric: settings.notchHUDConfiguration.metric,
        warning: configurationBinding(\.warningThreshold),
        critical: configurationBinding(\.criticalThreshold),
        warningIdentifier: "notchIndicatorWarningField",
        criticalIdentifier: "notchIndicatorCriticalField")

      if let secondaryMetric = settings.notchHUDConfiguration.secondaryMetric {
        Divider()
        thresholdRow(
          title: L10n.string("Indicator 2"),
          metric: secondaryMetric,
          warning: secondaryWarningBinding,
          critical: secondaryCriticalBinding,
          warningIdentifier: "notchIndicatorSecondaryWarningField",
          criticalIdentifier: "notchIndicatorSecondaryCriticalField")
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
      .accessibilityIdentifier("notchHUDSimulatedDisplayToggle")
    }
  }

  private var resetRow: some View {
    HStack {
      Text(L10n.string("Choose one sensor or split the contour between two sensors."))
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

  private var indicatorCountBinding: Binding<NotchIndicatorCount> {
    Binding(
      get: { settings.notchHUDConfiguration.indicatorCount },
      set: { count in
        settings.notchHUDConfiguration = NotchHUDConfigurationPolicy.settingIndicatorCount(
          count,
          in: settings.notchHUDConfiguration)
      })
  }

  private var primaryMetricBinding: Binding<MenuMetric> {
    Binding(
      get: { settings.notchHUDConfiguration.metric },
      set: { settings.setNotchHUDMetric($0, side: .left) })
  }

  private var secondaryMetricBinding: Binding<MenuMetric> {
    Binding(
      get: {
        settings.notchHUDConfiguration.secondaryMetric
          ?? availableSecondaryMetrics.first
          ?? .temperature
      },
      set: { settings.setNotchHUDMetric($0, side: .right) })
  }

  private var availableSecondaryMetrics: [MenuMetric] {
    MenuMetric.notchIndicatorMetrics.filter {
      $0 != settings.notchHUDConfiguration.metric
    }
  }

  private var secondaryWarningBinding: Binding<Double> {
    Binding(
      get: {
        let metric = settings.notchHUDConfiguration.secondaryMetric ?? .temperature
        return settings.notchHUDConfiguration.secondaryWarningThreshold
          ?? metric.notchIndicatorDefaultThresholds.warning
      },
      set: { newValue in
        var configuration = settings.notchHUDConfiguration
        configuration.secondaryWarningThreshold = newValue
        settings.notchHUDConfiguration = configuration
      })
  }

  private var secondaryCriticalBinding: Binding<Double> {
    Binding(
      get: {
        let metric = settings.notchHUDConfiguration.secondaryMetric ?? .temperature
        return settings.notchHUDConfiguration.secondaryCriticalThreshold
          ?? metric.notchIndicatorDefaultThresholds.critical
      },
      set: { newValue in
        var configuration = settings.notchHUDConfiguration
        configuration.secondaryCriticalThreshold = newValue
        settings.notchHUDConfiguration = configuration
      })
  }

  private var indicatorCountDescription: String {
    settings.notchHUDConfiguration.indicatorCount == .one
      ? L10n.string("One indicator keeps the current full-contour behavior.")
      : L10n.string("The first sensor fills the left half and the second fills the right half.")
  }

  private func metricPicker(
    selection: Binding<MenuMetric>,
    metrics: [MenuMetric],
    identifier: String
  ) -> some View {
    Picker(L10n.string("Displayed sensor"), selection: selection) {
      ForEach(metrics) { metric in
        Label(metric.displayName, systemImage: metric.defaultSymbol)
          .tag(metric)
      }
    }
    .labelsHidden()
    .pickerStyle(.menu)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier(identifier)
  }

  private func thresholdRow(
    title: String,
    metric: MenuMetric,
    warning: Binding<Double>,
    critical: Binding<Double>,
    warningIdentifier: String,
    criticalIdentifier: String
  ) -> some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text("\(title) · \(metric.displayName)")
          .font(.subheadline.weight(.semibold))
        Text(thresholdDescription(for: metric))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()

      thresholdField(
        title: L10n.string("Warning"),
        value: warning,
        identifier: warningIdentifier)
      thresholdField(
        title: L10n.string("Critical"),
        value: critical,
        identifier: criticalIdentifier)
    }
  }

  private func thresholdDescription(for metric: MenuMetric) -> String {
    metric.notchIndicatorLowerIsWorse
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
