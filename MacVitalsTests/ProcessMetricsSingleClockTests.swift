import XCTest
@testable import MacVitals

final class ProcessMetricsSingleClockTests: XCTestCase {
  func testEqualCadenceSubscribersReceiveOneSharedSample() async throws {
    let sampling = SamplingProbe()
    let deliveries = DeliveryProbe()
    let center = makeCenter(probe: sampling)
    let firstID = UUID()
    let secondID = UUID()

    await center.subscribe(firstID, minimumInterval: 1) { snapshot in
      await deliveries.record(snapshot, for: firstID)
    }
    await center.subscribe(secondID, minimumInterval: 1) { snapshot in
      await deliveries.record(snapshot, for: secondID)
    }

    let left = await deliveries.firstSnapshot(for: firstID)
    let right = await deliveries.firstSnapshot(for: secondID)

    XCTAssertEqual(left, right)
    XCTAssertGreaterThan(left.sampledProcessCount, 0)
    let counts = await sampling.counts()
    XCTAssertEqual(
      counts.samples,
      1,
      "Equal-cadence subscribers must share the first provider operation")

    await center.unsubscribe(firstID)
    await center.unsubscribe(secondID)
  }

  func testClockContinuesUntilLastSubscriberStops() async throws {
    let probe = SamplingProbe()
    let center = makeCenter(probe: probe)
    let firstID = UUID()
    let secondID = UUID()

    await center.subscribe(firstID, minimumInterval: 0.25) { _ in }
    await center.subscribe(secondID, minimumInterval: 0.25) { _ in }
    try await Task.sleep(for: .milliseconds(650))
    let withTwo = (await probe.counts()).samples
    XCTAssertGreaterThanOrEqual(withTwo, 2)

    await center.unsubscribe(firstID)
    try await Task.sleep(for: .milliseconds(350))
    let withOne = (await probe.counts()).samples
    XCTAssertGreaterThan(withOne, withTwo, "Remaining subscriber must keep the shared clock alive")

    await center.unsubscribe(secondID)
    try await Task.sleep(for: .milliseconds(100))
    let stopped = (await probe.counts()).samples
    try await Task.sleep(for: .milliseconds(400))
    let afterStop = (await probe.counts()).samples
    XCTAssertEqual(
      afterStop,
      stopped,
      "Last-subscriber removal must stop recurring process sampling")
  }

  func testIdleToActiveRestartResetsProviderExactlyOncePerSession() async throws {
    let probe = SamplingProbe()
    let deliveries = DeliveryProbe()
    let center = makeCenter(probe: probe)
    let firstID = UUID()
    let secondID = UUID()

    await center.subscribe(firstID, minimumInterval: 1) { snapshot in
      await deliveries.record(snapshot, for: firstID)
    }
    _ = await deliveries.firstSnapshot(for: firstID)
    await center.unsubscribe(firstID)

    await center.subscribe(secondID, minimumInterval: 1) { snapshot in
      await deliveries.record(snapshot, for: secondID)
    }
    _ = await deliveries.firstSnapshot(for: secondID)
    await center.unsubscribe(secondID)

    let counts = await probe.counts()
    XCTAssertEqual(counts.resets, 2)
    XCTAssertEqual(counts.samples, 2)
  }

  func testFasterSubscriberAdvancesTheOneSharedClockWithoutAnotherConsumerLoop() async throws {
    let probe = SamplingProbe()
    let deliveries = DeliveryProbe()
    let center = makeCenter(probe: probe)
    let slowID = UUID()
    let fastID = UUID()

    await center.subscribe(slowID, minimumInterval: 2) { snapshot in
      await deliveries.record(snapshot, for: slowID)
    }
    let firstSlow = await deliveries.firstSnapshot(for: slowID)

    await center.subscribe(fastID, minimumInterval: 0.25) { snapshot in
      await deliveries.record(snapshot, for: fastID)
    }
    let firstFast = await deliveries.firstSnapshot(for: fastID)
    XCTAssertEqual(
      firstFast,
      firstSlow,
      "A fresh cached sample should be delivered directly to a joining subscriber")

    try await Task.sleep(for: .milliseconds(650))
    let counts = await probe.counts()
    XCTAssertGreaterThanOrEqual(counts.samples, 2, "Faster subscriber must advance the shared cadence")
    XCTAssertEqual(
      counts.resets,
      1,
      "Cadence changes inside an active session must not reset provider baselines")

    await center.unsubscribe(slowID)
    await center.unsubscribe(fastID)
  }

  func testCadenceChangeDoesNotDeliverCancelledInFlightSample() async throws {
    let probe = BlockingSamplingProbe()
    let deliveries = DeliveryProbe()
    let center = ProcessMetricsSamplingCenter(
      resetProvider: {},
      sampleProvider: { applications in await probe.sample(applications: applications) },
      runningApplicationsProvider: { [] })
    let slowID = UUID()
    let fastID = UUID()

    await center.subscribe(slowID, minimumInterval: 2) { snapshot in
      await deliveries.record(snapshot, for: slowID)
    }
    await probe.waitUntilFirstSampleStarts()

    await center.subscribe(fastID, minimumInterval: 0.25) { snapshot in
      await deliveries.record(snapshot, for: fastID)
    }
    let fastSnapshot = await deliveries.firstSnapshot(for: fastID)
    XCTAssertEqual(
      fastSnapshot.sampledProcessCount,
      2,
      "Replacement clock must deliver its own sample while the cancelled sample is still blocked")

    await probe.releaseFirstSample()
    try await Task.sleep(for: .milliseconds(50))
    let slowSnapshot = await deliveries.firstSnapshot(for: slowID)
    XCTAssertEqual(
      slowSnapshot.sampledProcessCount,
      2,
      "Cancelled in-flight completion must not replace the current shared snapshot")

    await center.unsubscribe(slowID)
    await center.unsubscribe(fastID)
  }

  func testReplacingSubscriberIDCannotCommitOldHandlerDeliveryState() async throws {
    let sampling = SamplingProbe()
    let deliveries = BlockingDeliveryProbe()
    let center = makeCenter(probe: sampling)
    let id = UUID()

    await center.subscribe(id, minimumInterval: 0.25) { snapshot in
      await deliveries.blockFirstDelivery(snapshot)
    }
    await deliveries.waitUntilFirstDeliveryStarts()

    await center.subscribe(id, minimumInterval: 0.25) { snapshot in
      await deliveries.recordReplacement(snapshot)
    }
    await deliveries.releaseFirstDelivery()

    let replacement = await deliveries.firstReplacementSnapshot()
    XCTAssertGreaterThan(replacement.sampledProcessCount, 0)
    try await Task.sleep(for: .milliseconds(350))
    XCTAssertGreaterThanOrEqual(
      await deliveries.replacementCount(),
      1,
      "Replacing a subscriber while an old async handler is suspended must keep the new handler registered")

    await center.unsubscribe(id)
  }

  private func makeCenter(probe: SamplingProbe) -> ProcessMetricsSamplingCenter {
    ProcessMetricsSamplingCenter(
      resetProvider: { await probe.reset() },
      sampleProvider: { applications in await probe.sample(applications: applications) },
      runningApplicationsProvider: { [] })
  }
}

private actor DeliveryProbe {
  private var snapshots: [UUID: [ProcessMetricsSnapshot]] = [:]
  private var waiters: [UUID: [CheckedContinuation<ProcessMetricsSnapshot, Never>]] = [:]

  func record(_ snapshot: ProcessMetricsSnapshot, for id: UUID) {
    if var pending = waiters[id], !pending.isEmpty {
      let waiter = pending.removeFirst()
      waiters[id] = pending
      waiter.resume(returning: snapshot)
      return
    }
    snapshots[id, default: []].append(snapshot)
  }

  func firstSnapshot(for id: UUID) async -> ProcessMetricsSnapshot {
    if var values = snapshots[id], !values.isEmpty {
      let first = values.removeFirst()
      snapshots[id] = values
      return first
    }
    return await withCheckedContinuation { continuation in
      waiters[id, default: []].append(continuation)
    }
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
      timestamp: Date(),
      applications: [],
      sampledProcessCount: max(1, applications.count, sampleCount),
      energyCountersAvailable: false)
  }

  func counts() -> (resets: Int, samples: Int) {
    (resetCount, sampleCount)
  }
}

private actor BlockingSamplingProbe {
  private var sampleCount = 0
  private var firstSampleStarted = false
  private var firstSampleReleased = false
  private var firstStartWaiters: [CheckedContinuation<Void, Never>] = []
  private var firstReleaseContinuation: CheckedContinuation<Void, Never>?

  func waitUntilFirstSampleStarts() async {
    if firstSampleStarted { return }
    await withCheckedContinuation { continuation in
      firstStartWaiters.append(continuation)
    }
  }

  func releaseFirstSample() {
    firstSampleReleased = true
    firstReleaseContinuation?.resume()
    firstReleaseContinuation = nil
  }

  func sample(applications: [RunningApplicationDescriptor]) async -> ProcessMetricsSnapshot {
    sampleCount += 1
    let ordinal = sampleCount

    if ordinal == 1 {
      firstSampleStarted = true
      let waiters = firstStartWaiters
      firstStartWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
      if !firstSampleReleased {
        await withCheckedContinuation { continuation in
          firstReleaseContinuation = continuation
        }
      }
    }

    return ProcessMetricsSnapshot(
      timestamp: Date(),
      applications: [],
      sampledProcessCount: ordinal,
      energyCountersAvailable: false)
  }
}

private actor BlockingDeliveryProbe {
  private var firstDeliveryStarted = false
  private var firstDeliveryReleased = false
  private var firstStartWaiters: [CheckedContinuation<Void, Never>] = []
  private var firstReleaseContinuation: CheckedContinuation<Void, Never>?
  private var replacementSnapshots: [ProcessMetricsSnapshot] = []
  private var replacementWaiters: [CheckedContinuation<ProcessMetricsSnapshot, Never>] = []

  func blockFirstDelivery(_ snapshot: ProcessMetricsSnapshot) async {
    firstDeliveryStarted = true
    let waiters = firstStartWaiters
    firstStartWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
    if !firstDeliveryReleased {
      await withCheckedContinuation { continuation in
        firstReleaseContinuation = continuation
      }
    }
  }

  func waitUntilFirstDeliveryStarts() async {
    if firstDeliveryStarted { return }
    await withCheckedContinuation { continuation in
      firstStartWaiters.append(continuation)
    }
  }

  func releaseFirstDelivery() {
    firstDeliveryReleased = true
    firstReleaseContinuation?.resume()
    firstReleaseContinuation = nil
  }

  func recordReplacement(_ snapshot: ProcessMetricsSnapshot) {
    if !replacementWaiters.isEmpty {
      let waiter = replacementWaiters.removeFirst()
      waiter.resume(returning: snapshot)
      return
    }
    replacementSnapshots.append(snapshot)
  }

  func firstReplacementSnapshot() async -> ProcessMetricsSnapshot {
    if !replacementSnapshots.isEmpty {
      return replacementSnapshots.removeFirst()
    }
    return await withCheckedContinuation { continuation in
      replacementWaiters.append(continuation)
    }
  }

  func replacementCount() -> Int {
    replacementSnapshots.count
  }
}
