import Foundation

nonisolated struct TimedPoint: Codable, Sendable, Equatable, Identifiable {
  let id: UUID
  let timestamp: Date
  let value: Double?
  let discontinuity: Bool

  init(timestamp: Date = Date(), value: Double?, discontinuity: Bool = false) {
    self.id = UUID()
    self.timestamp = timestamp
    self.value = value
    self.discontinuity = discontinuity
  }
}

nonisolated struct HistoryChartPoint: Sendable, Equatable, Identifiable {
  let id: UUID
  let timestamp: Date
  let value: Double
  let segment: Int
}

nonisolated enum HistoryChartSegmentation {
  static func points(from history: [TimedPoint]) -> [HistoryChartPoint] {
    var result: [HistoryChartPoint] = []
    result.reserveCapacity(history.count)

    var segment = 0
    var breakPending = false

    for point in history {
      if point.discontinuity {
        breakPending = !result.isEmpty
        continue
      }
      guard let value = point.value, value.isFinite else { continue }

      if breakPending {
        segment += 1
        breakPending = false
      }
      result.append(
        HistoryChartPoint(
          id: point.id,
          timestamp: point.timestamp,
          value: value,
          segment: segment))
    }
    return result
  }
}

nonisolated struct RingBuffer<Element: Sendable>: Sendable {
  private var storage: [Element] = []
  let capacity: Int

  init(capacity: Int) { self.capacity = max(1, capacity) }

  var values: [Element] { storage }

  mutating func append(_ element: Element) {
    if storage.count == capacity { storage.removeFirst() }
    storage.append(element)
  }

  mutating func removeAll() { storage.removeAll(keepingCapacity: true) }
}
