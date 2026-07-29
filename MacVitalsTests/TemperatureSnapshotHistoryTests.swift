import XCTest
@testable import MacVitals

final class TemperatureSnapshotHistoryTests: XCTestCase {
  func testTemperatureHistoryPrefersProcessorReading() {
    let timestamp = Date(timeIntervalSince1970: 123)
    let snapshot = SystemSnapshot(
      timestamp: timestamp,
      cpu: .unavailable(unit: .percent),
      memory: .unavailable(unit: .bytes),
      battery: .unavailable(unit: .percent),
      adapter: .unavailable(unit: .watts),
      gpu: .unavailable(unit: .percent),
      temperature: MetricValue(
        value: TemperatureStats(
          processorCelsius: 65,
          batteryCelsius: 31,
          maximumCelsius: 65,
          processorSensorKey: "TCMz"),
        unit: .celsius,
        availability: .available,
        quality: .experimental,
        source: .appleSMC,
        timestamp: timestamp,
        isEstimated: false,
        message: nil),
      power: .unavailable(unit: .watts))

    let points = SnapshotHistoryPoints.make(from: snapshot)

    XCTAssertEqual(points.temperature.timestamp, timestamp)
    XCTAssertEqual(points.temperature.value, 65)
  }
}
