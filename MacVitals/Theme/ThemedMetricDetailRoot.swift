import SwiftUI

struct ThemedMetricDetailRoot<Content: View>: View {
  @ObservedObject private var themeController: ThemeController
  private let metric: MetricKind
  private let content: Content

  init(
    metric: MetricKind,
    themeController: ThemeController = .shared,
    @ViewBuilder content: () -> Content
  ) {
    self.metric = metric
    self.themeController = themeController
    self.content = content()
  }

  var body: some View {
    ThemedOverviewRoot(themeController: themeController) {
      content.metricTheme(themeController.theme, metric: metric)
    }
  }
}
