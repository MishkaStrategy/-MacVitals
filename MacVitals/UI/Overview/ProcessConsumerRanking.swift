import Foundation

nonisolated struct RankedApplicationProcessUsage: Identifiable, Sendable, Equatable {
  let rank: Int
  let application: ApplicationProcessUsage

  var id: String { application.id }
}

nonisolated enum ProcessConsumerRanking {
  static func topApplications(
    _ applications: [ApplicationProcessUsage],
    metric: ProcessConsumerMetric,
    limit: Int = 10
  ) -> [RankedApplicationProcessUsage] {
    guard limit > 0 else { return [] }

    return applications
      .filter(isVisible)
      .sorted { lhs, rhs in
        let left = sortValue(lhs, metric: metric)
        let right = sortValue(rhs, metric: metric)
        if left == right {
          return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return left > right
      }
      .prefix(limit)
      .enumerated()
      .map { offset, application in
        RankedApplicationProcessUsage(rank: offset + 1, application: application)
      }
  }

  private static func isVisible(_ application: ApplicationProcessUsage) -> Bool {
    application.memoryBytes > 1_048_576
      || application.cpuPercent > 0.01
      || application.energyImpactScore > 0.01
      || application.gpuActivityScore > 0.01
  }

  private static func sortValue(
    _ application: ApplicationProcessUsage,
    metric: ProcessConsumerMetric
  ) -> Double {
    switch metric {
    case .cpu: return application.cpuPercent
    case .memory: return Double(application.memoryBytes)
    case .gpu: return application.gpuActivityScore
    case .energy: return application.energyWatts ?? application.energyImpactScore
    }
  }
}
