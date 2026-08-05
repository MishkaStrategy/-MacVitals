import Foundation

nonisolated struct ScalarHistoryChartModel: Sendable, Equatable {
  let points: [HistoryChartPoint]
  let yDomain: ClosedRange<Double>
}

nonisolated struct FanHistoryChartPoint: Identifiable, Sendable, Equatable {
  let id: UUID
  let timestamp: Date
  let value: Double
  let fanIndex: Int
  let segment: Int

  var seriesKey: String { "fan-\(fanIndex)-segment-\(segment)" }
  var fanLabel: String { L10n.format("Fan %d", fanIndex + 1) }
}

nonisolated struct FanHistoryChartModel: Sendable, Equatable {
  let points: [FanHistoryChartPoint]
  let yDomain: ClosedRange<Double>
}

nonisolated struct PowerHistorySeries: Sendable, Equatable {
  let name: String
  let history: [TimedPoint]
}

nonisolated struct PowerHistoryChartPoint: Identifiable, Sendable, Equatable {
  let id: UUID
  let timestamp: Date
  let value: Double
  let series: String
  let segment: Int

  var seriesKey: String { "\(series)-\(segment)" }
}

nonisolated struct PowerHistoryChartModel: Sendable, Equatable {
  let points: [PowerHistoryChartPoint]
  let yDomain: ClosedRange<Double>
}

nonisolated enum MetricHistoryChartModelBuilder {
  static func scalar(
    history: [TimedPoint],
    cutoff: Date,
    yDomain: ClosedRange<Double>
  ) -> ScalarHistoryChartModel {
    let values = scalarPoints(in: history, cutoff: cutoff)
    return ScalarHistoryChartModel(points: values.points, yDomain: yDomain)
  }

  static func temperature(
    history: [TimedPoint],
    cutoff: Date
  ) -> ScalarHistoryChartModel {
    let values = scalarPoints(in: history, cutoff: cutoff)
    let points = values.points
    let minimum = values.minimum
    let maximum = values.maximum

    let domain: ClosedRange<Double>
    if let minimum, let maximum {
      let lower = max(-10, floor(minimum / 10) * 10 - 10)
      let upper = min(140, max(lower + 20, ceil(maximum / 10) * 10 + 10))
      domain = lower...upper
    } else {
      domain = 0...120
    }

    return ScalarHistoryChartModel(points: points, yDomain: domain)
  }

  static func fans(
    histories: [Int: [TimedPoint]],
    cutoff: Date
  ) -> FanHistoryChartModel {
    var points: [FanHistoryChartPoint] = []
    points.reserveCapacity(histories.values.reduce(into: 0) { $0 += $1.count })
    var minimum: Double?
    var maximum: Double?

    for (fanIndex, history) in histories.sorted(by: { $0.key < $1.key }) {
      forEachSegmentedValue(in: history, cutoff: cutoff) { point, value, segment in
        points.append(
          FanHistoryChartPoint(
            id: point.id,
            timestamp: point.timestamp,
            value: value,
            fanIndex: fanIndex,
            segment: segment))
        minimum = min(minimum ?? value, value)
        maximum = max(maximum ?? value, value)
      }
    }

    let domain: ClosedRange<Double>
    if let minimum, let maximum {
      let lower = max(0, floor((minimum - 500) / 500) * 500)
      let upper = max(lower + 1_000, ceil((maximum + 500) / 500) * 500)
      domain = lower...upper
    } else {
      domain = 0...8_000
    }

    return FanHistoryChartModel(points: points, yDomain: domain)
  }

  static func power(
    series: [PowerHistorySeries],
    cutoff: Date
  ) -> PowerHistoryChartModel {
    var points: [PowerHistoryChartPoint] = []
    points.reserveCapacity(series.reduce(into: 0) { $0 += $1.history.count })
    var minimum = 0.0
    var maximum = 0.0

    for item in series {
      forEachSegmentedValue(in: item.history, cutoff: cutoff) { point, value, segment in
        points.append(
          PowerHistoryChartPoint(
            id: point.id,
            timestamp: point.timestamp,
            value: value,
            series: item.name,
            segment: segment))
        minimum = min(minimum, value)
        maximum = max(maximum, value)
      }
    }

    let padding = max(5, (maximum - minimum) * 0.15)
    let domain = floor(minimum - padding)...ceil(maximum + padding)
    return PowerHistoryChartModel(points: points, yDomain: domain)
  }

  private static func scalarPoints(
    in history: [TimedPoint],
    cutoff: Date
  ) -> (points: [HistoryChartPoint], minimum: Double?, maximum: Double?) {
    var points: [HistoryChartPoint] = []
    points.reserveCapacity(history.count)
    var minimum: Double?
    var maximum: Double?

    forEachSegmentedValue(in: history, cutoff: cutoff) { point, value, segment in
      points.append(
        HistoryChartPoint(
          id: point.id,
          timestamp: point.timestamp,
          value: value,
          segment: segment))
      minimum = min(minimum ?? value, value)
      maximum = max(maximum ?? value, value)
    }

    return (points, minimum, maximum)
  }

  private static func forEachSegmentedValue(
    in history: [TimedPoint],
    cutoff: Date,
    _ body: (TimedPoint, Double, Int) -> Void
  ) {
    var segment = 0
    var emittedValue = false
    var breakPending = false

    for point in history where point.timestamp >= cutoff {
      if point.discontinuity {
        breakPending = emittedValue
        continue
      }
      guard let value = point.value, value.isFinite else { continue }

      if breakPending {
        segment += 1
        breakPending = false
      }
      body(point, value, segment)
      emittedValue = true
    }
  }
}
