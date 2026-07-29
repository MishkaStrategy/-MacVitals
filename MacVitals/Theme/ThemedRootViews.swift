import AppKit
import SwiftUI

enum ThemeL10n {
  static func string(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: "Theme")
  }
}

private struct ThemeRootModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  let theme: AppTheme

  func body(content: Content) -> some View {
    content
      .appTheme(theme)
      .background {
        if reduceTransparency {
          Color(nsColor: .windowBackgroundColor)
        } else {
          Rectangle().fill(.ultraThinMaterial)
        }
      }
      .overlay(alignment: .top) {
        if contrast == .increased {
          Divider().opacity(0.9)
        }
      }
  }
}

struct ThemedOverviewRoot<Content: View>: View {
  @ObservedObject private var themeController: ThemeController
  private let content: Content

  init(
    themeController: ThemeController = .shared,
    @ViewBuilder content: () -> Content
  ) {
    self.themeController = themeController
    self.content = content()
  }

  var body: some View {
    content.modifier(ThemeRootModifier(theme: themeController.theme))
  }
}

struct ThemedPreferencesRootView: View {
  @ObservedObject private var themeController: ThemeController

  init(themeController: ThemeController = .shared) {
    self.themeController = themeController
  }

  var body: some View {
    VStack(spacing: 0) {
      themeSelector
      Divider()
      PreferencesView()
    }
    .modifier(ThemeRootModifier(theme: themeController.theme))
    .frame(minWidth: 860, minHeight: 700)
  }

  private var themeSelector: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(ThemeL10n.string("Interface color scheme"))
            .font(.headline)
          Text(ThemeL10n.string("Choose a quiet two-color interface or metric-specific accents."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Picker(
          ThemeL10n.string("Interface color scheme"),
          selection: $themeController.style
        ) {
          Text(ThemeL10n.string("Two-color")).tag(ColorSchemeStyle.duotone)
          Text(ThemeL10n.string("Multicolor")).tag(ColorSchemeStyle.multicolor)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 250)
        .accessibilityIdentifier("colorSchemePicker")
        .accessibilityLabel(ThemeL10n.string("Interface color scheme"))
      }

      HStack(spacing: 12) {
        ThemePreviewCard(
          style: .duotone,
          isSelected: themeController.style == .duotone,
          action: { themeController.style = .duotone })
        ThemePreviewCard(
          style: .multicolor,
          isSelected: themeController.style == .multicolor,
          action: { themeController.style = .multicolor })
      }
    }
    .padding(.horizontal, 24)
    .padding(.top, 18)
    .padding(.bottom, 14)
    .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
  }
}

private struct ThemePreviewCard: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  let style: ColorSchemeStyle
  let isSelected: Bool
  let action: () -> Void

  private var theme: AppTheme { AppTheme(style: style) }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        VStack(spacing: 5) {
          previewRow(.cpu, width: 54)
          previewRow(.memory, width: 42)
          previewRow(.gpu, width: 49)
          previewRow(.battery, width: 36)
        }
        .frame(width: 64)

        VStack(alignment: .leading, spacing: 3) {
          Text(style == .duotone ? ThemeL10n.string("Two-color") : ThemeL10n.string("Multicolor"))
            .font(.subheadline.weight(.semibold))
          Text(
            style == .duotone
              ? ThemeL10n.string("System surfaces and blue accents")
              : ThemeL10n.string("A distinct accent for every metric")
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        }
        Spacer(minLength: 4)
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? theme.primaryAccent : Color.secondary)
      }
      .padding(12)
      .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
      .background(
        reduceTransparency
          ? Color(nsColor: .controlBackgroundColor)
          : Color.primary.opacity(isSelected ? 0.075 : 0.035),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(
            isSelected
              ? theme.primaryAccent.opacity(contrast == .increased ? 0.95 : 0.55)
              : Color.secondary.opacity(contrast == .increased ? 0.55 : 0.18),
            lineWidth: contrast == .increased ? 1.5 : 1)
      }
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("themePreview.\(style.rawValue)")
    .accessibilityLabel(
      style == .duotone ? ThemeL10n.string("Two-color scheme") : ThemeL10n.string("Multicolor scheme"))
    .accessibilityValue(isSelected ? ThemeL10n.string("Selected") : ThemeL10n.string("Not selected"))
  }

  private func previewRow(_ metric: MetricKind, width: CGFloat) -> some View {
    HStack(spacing: 5) {
      Circle()
        .fill(theme.color(for: metric))
        .frame(width: 6, height: 6)
      Capsule()
        .fill(theme.color(for: metric).opacity(0.72))
        .frame(width: width, height: 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
