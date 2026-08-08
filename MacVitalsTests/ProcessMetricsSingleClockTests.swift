import XCTest
@testable import MacVitals

final class ProcessMetricsSingleClockTests: XCTestCase {
  func testEqualCadenceSubscribersReceiveOneSharedSample() async throws {
    let probe = SamplingProbe()
    let center = makeCenter(probe: probe)
    let firstID = UUID()
    let secondID = UUID()

    let firstStream = await center.subscribe(firstID, minimumInterval: 0.25)
    let secondStream = await center.subscribe(secondID, minimumInterval: 0.25)

    async let first = firstSnapshot(from: firstStream)
    async let second = firstSnapshot(from: secondStream)
    let (left, right) = try await (first, second)

    XCTAssertEqual(left, right)
    XCTAssertGreaterThan(left.sampledProcessCount, 0)
    let counts = await probe.counts()
    XCTAssertEqual(counts.samples, 1, "Equal-cadence subscribers must share the first provider operation")

    await center.unsubscribe(firstID)
    await center.unsubscribe(secondID)
  }

  func testClockContinuesUntilLastSubscriberStops() async throws {
    let probe = SamplingProbe()
    let center = makeCenter(probe: probe)
    let firstID = UUID()
    let secondID = UUID()

    _ = await center.subscribe(firstID, minimumInterval: 0.25)
    _ = await center.subscribe(secondID, minimumInterval: 0.25)
    try await Task.sleep(for: .milliseconds(650))
    let withTwo = await probe.counts().samples
    XCTAssertGreaterThanOrEqual(withTwo, 2)

    await center.unsubscribe(firstID)
    try await Task.sleep(for: .milliseconds(350))
    let withOne = await probe.counts().samples
    XCTAssertGreaterThan(withOne, withTwo, "Remaining subscriber must keep the shared clock alive")

    await center.unsubscribe(secondID)
    try await Task.sleep(for: .milliseconds(100))
    let stopped = await probe.counts().samples
    try await Task.sleep(for: .milliseconds(400))
    XCTAssertEqual(
      await probe.counts().samples,
      stopped,
      "Last-subscriber removal must stop recurring process sampling")
  }

  func testIdleToActiveRestartResetsProviderExactlyOncePerSession() async throws {
    let probe = SamplingProbe()
    let center = makeCenter(probe: probe)
    let firstID = UUID()
    let secondID = UUID()

    let firstStream = await center.subscribe(firstID, minimumInterval: 1)
    _ = try await firstSnapshot(from: firstStream)
    await center.unsubscribe(firstID)

    let secondStream = await center.subscribe(secondID, minimumInterval: 1)
    _ = try await firstSnapshot(from: secondStream)
    await center.unsubscribe(secondID)

    let counts = await probe.counts()
    XCTAssertEqual(counts.resets, 2)
    XCTAssertEqual(counts.samples, 2)
  }

  func testFasterSubscriberAdvancesTheOneSharedClock() async throws {
    let probe = SamplingProbe()
    let center = makeCenter(probe: probe)
    let slowID = UUID()
    let fastID = UUID()

    let slowStream = await center.subscribe(slowID, minimumInterval: 2)
    let firstSlow = try await firstSnapshot(from: slowStream)

    let fastStream = await center.subscribe(fastID, minimumInterval: 0.25)
    let firstFast = try await firstSnapshot(from: fastStream)
    XCTAssertEqual(firstFast, firstSlow, "A fresh cached sample should be shared with a joining subscriber")

    try await Task.sleep(for: .milliseconds(650))
    let counts = await probe.counts()
    XCTAssertGreaterThanOrEqual(counts.samples, 2, "Faster subscriber must advance the shared cadence")
    XCTAssertEqual(counts.resets, 1, "Cadence changes inside an active session must not reset provider baselines")

    await center.unsubscribe(slowID)
    await center.unsubscribe(fastID)
  }

  private func makeCenter(probe: SamplingProbe) -> ProcessMetricsSamplingCenter {
    ProcessMetricsSamplingCenter(
      resetProvider: { await probe.reset() },
      sampleProvider: { applications in await probe.sample(applications: applications) },
      runningApplicationsProvider: { [] })
  }

  private func firstSnapshot(from stream: AsyncStream<ProcessMetricsSnapshot>) async throws
    -> ProcessMetricsSnapshot
  {
    var iterator = stream.makeAsyncIterator()
    guard let snapshot = await iterator.next() else {
      XCTFail("Shared process sampling stream ended before publishing a snapshot")
      throw TestError.missingSnapshot
    }
    return snapshot
  }

  private enum TestError: Error {
    case missingSnapshot
  }
}

private actor SamplingProbe {
  private var resetCount = 0
  private var sampleCount = 0

  func reset() {
    resetCount += 1
  }

  func sample(applications: [RunningApplicationDescriptor]) -> ProcessMetricsSnapshot {
    sampleCount += 1
    return ProcessMetricsSnapshot(
      timestamp: Date(timeIntervalSince1970: TimeInterval(sampleCount)),
      applications: [],
      sampledProcessCount: max(1, applications.count),
      energyCountersAvailable: false)
  }

  func counts() -> (resets: Int, samples: Int) {
    (resetCount, sampleCount)
  }
}
