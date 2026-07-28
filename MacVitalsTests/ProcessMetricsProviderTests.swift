import Darwin
import XCTest

@testable import MacVitals

final class ProcessMetricsProviderTests: XCTestCase {
  func testCounterDeltaCalculatesCPUAndEnergyRate() {
    let previous = sample(
      cpu: 1_000_000_000,
      energy: 2_000_000_000,
      read: 100,
      write: 200)
    let current = sample(
      cpu: 3_000_000_000,
      energy: 3_000_000_000,
      read: 1_100,
      write: 1_200)

    let delta = ProcessCounterCalculator.delta(
      previous: previous,
      current: current,
      elapsedSeconds: 2)

    XCTAssertEqual(delta.cpuPercent, 100, accuracy: 0.0001)
    XCTAssertEqual(delta.energyWatts ?? -1, 0.5, accuracy: 0.0001)
    XCTAssertEqual(delta.diskBytesPerSecond, 1_000, accuracy: 0.0001)
  }

  func testCounterDeltaRejectsPIDReuse() {
    let previous = sample(cpu: 100, energy: 100, startTime: 1)
    let current = sample(cpu: 10_000, energy: 10_000, startTime: 2)

    let delta = ProcessCounterCalculator.delta(
      previous: previous,
      current: current,
      elapsedSeconds: 1)

    XCTAssertEqual(delta.cpuPercent, 0)
    XCTAssertNil(delta.energyWatts)
    XCTAssertEqual(delta.diskBytesPerSecond, 0)
  }

  func testCounterDeltaHandlesCounterReset() {
    let previous = sample(cpu: 5_000, energy: 5_000, read: 5_000, write: 5_000)
    let current = sample(cpu: 100, energy: 100, read: 100, write: 100)

    let delta = ProcessCounterCalculator.delta(
      previous: previous,
      current: current,
      elapsedSeconds: 1)

    XCTAssertEqual(delta.cpuPercent, 0)
    XCTAssertNil(delta.energyWatts)
    XCTAssertEqual(delta.diskBytesPerSecond, 0)
  }

  func testNormalizedScoresKeepRelativeOrder() {
    let scores = ProcessCounterCalculator.normalizedScores([0, 5, 10, .nan])

    XCTAssertEqual(scores.count, 4)
    XCTAssertEqual(scores[0], 0)
    XCTAssertEqual(scores[1], 50, accuracy: 0.0001)
    XCTAssertEqual(scores[2], 100, accuracy: 0.0001)
    XCTAssertEqual(scores[3], 0)
  }

  private func sample(
    cpu: UInt64,
    energy: UInt64?,
    read: UInt64? = 0,
    write: UInt64? = 0,
    startTime: UInt64 = 1
  ) -> ProcessCounterSample {
    ProcessCounterSample(
      pid: 42,
      startTime: startTime,
      name: "Test App",
      executablePath: "/Applications/Test App.app/Contents/MacOS/Test App",
      cpuTimeNanoseconds: cpu,
      physicalFootprintBytes: 512 * 1_024 * 1_024,
      energyNanojoules: energy,
      diskReadBytes: read,
      diskWriteBytes: write)
  }
}
