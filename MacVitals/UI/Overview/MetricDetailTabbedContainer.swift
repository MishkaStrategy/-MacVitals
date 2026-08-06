import SwiftUI

private enum MetricDetailTab: String, CaseIterable, Identifiable {
  case overview
  case consumptionLeaders

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: return ConsumptionHistoryL10n.string("Overview")
    case .consumptionLeaders:
      return ConsumptionHistoryL10n.string("Consumption leaders")
    }
  }
}

struct MetricDetailTabbedContainer: View {
  @State private var selectedTab: MetricDetailTab = .overview
  let kind: MetricDetailKind

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Picker("Section", selection: $selectedTab) {
          ForEach(MetricDetailTab.allCases) { tab in
            Text(tab.title).tag(tab)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 300)
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 8)

      Divider()

      switch selectedTab {
      case .overview:
        MetricDetailView(kind: kind)
      case .consumptionLeaders:
        HistoricalConsumptionLeadersView(metric: kind.historicalConsumptionMetric)
          .padding(16)
          .frame(width: leaderWidth, height: leaderHeight)
      }
    }
  }

  private var leaderWidth: CGFloat {
    switch kind {
    case .fans, .temperature, .power: return 700
    case .cpu, .memory, .gpu, .battery: return 740
    }
  }

  private var leaderHeight: CGFloat {
    switch kind {
    case .fans, .temperature, .power: return 610
    case .cpu, .memory, .gpu, .battery: return 660
    }
  }
}

extension MetricDetailKind {
  var historicalConsumptionMetric: HistoricalConsumptionMetric {
    switch self {
    case .cpu: return .cpu
    case .memory: return .memory
    case .gpu: return .gpu
    case .battery, .power: return .energy
    case .temperature, .fans: return .thermal
    }
  }
}
