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
  private var startIndex = 0
  let capacity: Int

  init(capacity: Int) {
    self.capacity = max(1, capacity)
    storage.reserveCapacity(self.capacity)
  }

  var values: [Element] {
    guard !storage.isEmpty else { return [] }
    guard storage.count == capacity, startIndex != 0 else { return storage }

    var result: [Element] = []
    result.reserveCapacity(storage.count)
    result.append(contentsOf: storage[startIndex...])
    result.append(contentsOf: storage[..<startIndex])
    return result
  }

  mutating func append(_ element: Element) {
    if storage.count < capacity {
      storage.append(element)
      return
    }

    storage[startIndex] = element
    startIndex = (startIndex + 1) % capacity
  }

  mutating func removeAll() {
    storage.removeAll(keepingCapacity: true)
    startIndex = 0
  }
}
