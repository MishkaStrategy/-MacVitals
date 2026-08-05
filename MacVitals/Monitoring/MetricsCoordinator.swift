import Combine
import Foundation
import OSLog

nonisolated struct SnapshotHistoryPoints: Sendable, Equatable {
  let cpu: TimedPoint
  let memory: TimedPoint
  let gpu: TimedPoint
  let battery: TimedPoint
  let temperature: TimedPoint
  let systemPower: TimedPoint
  let batteryPower: TimedPoint
  let adapterInputPower: TimedPoint

  static func make(from snapshot: SystemSnapshot) -> Self {
    Self(
      cpu: TimedPoint(timestamp: snapshot.timestamp, value: snapshot.cpu.value?.total),
      memory: TimedPoint(timestamp: snapshot.timestamp, value: snapshot.memory.value?.usedPercent),
      gpu: TimedPoint(
        timestamp: snapshot.timestamp,
        value: snapshot.gpu.value?.systemUtilizationPercent),
      battery: TimedPoint(timestamp: snapshot.timestamp, value: snapshot.battery.value?.percentage),
      temperature: TimedPoint(
        timestamp: snapshot.timestamp,
        value: snapshot.temperature.value?.processorCelsius
          ?? snapshot.temperature.value?.maximumCelsius),
      systemPower: TimedPoint(
        timestamp: snapshot.timestamp,
        value: snapshot.power.value?.estimatedSystemPowerWatts),
      batteryPower: TimedPoint(
        timestamp: snapshot.timestamp,
        value: snapshot.power.value?.batteryPowerWatts ?? snapshot.battery.value?.batteryPowerWatts),
      adapterInputPower: TimedPoint(
        timestamp: snapshot.timestamp,
        value: snapshot.power.value?.adapterInputPowerWatts))
  }
}

@MainActor
final class MetricsCoordinator: ObservableObject {
  @Published private(set) var snapshot: SystemSnapshot = .empty
  @Published private(set) var samplingHealth: SamplingHealth?
  @Published private(set) var isRunning = false

  var cpuHistory: [TimedPoint] { cpuBuffer.values }
  var memoryHistory: [TimedPoint] { memoryBuffer.values }
  var gpuHistory: [TimedPoint] { gpuBuffer.values }
  var batteryHistory: [TimedPoint] { batteryBuffer.values }
  var temperatureHistory: [TimedPoint] { temperatureBuffer.values }
  var temperatureSensorHistory: [String: [TimedPoint]] {
    temperatureSensorBuffers.mapValues(\.values)
  }
  var systemPowerHistory: [TimedPoint] { systemPowerBuffer.values }
  var batteryPowerHistory: [TimedPoint] { batteryPowerBuffer.values }
  var adapterInputPowerHistory: [TimedPoint] { adapterInputPowerBuffer.values }
  var fanHistory: [Int: [TimedPoint]] { fanBuffers.mapValues(\.values) }

  var onSnapshot: ((SystemSnapshot) -> Void)?

  private let sampler = SystemSampler()
  private var cpuBuffer: RingBuffer<TimedPoint>
  private var memoryBuffer: RingBuffer<TimedPoint>
  private var gpuBuffer: RingBuffer<TimedPoint>
  private var batteryBuffer: RingBuffer<TimedPoint>
  private var temperatureBuffer: RingBuffer<TimedPoint>
  private var temperatureSensorBuffers: [String: RingBuffer<TimedPoint>] = [:]
  private var systemPowerBuffer: RingBuffer<TimedPoint>
  private var batteryPowerBuffer: RingBuffer<TimedPoint>
  private var adapterInputPowerBuffer: RingBuffer<TimedPoint>
  private var fanBuffers: [Int: RingBuffer<TimedPoint>] = [:]
  private var samplingTask: Task<Void, Never>?
  private var configuredInterval: TimeInterval
  private var historyCapacity: Int

  init() {
    let interval = SamplingIntervalPolicy.normalized(
      UserDefaults.standard.double(forKey: "samplingInterval"))
    let capacity = SamplingIntervalPolicy.historyCapacity(for: interval)
    configuredInterval = interval
    historyCapacity = capacity
    cpuBuffer = RingBuffer(capacity: capacity)
    memoryBuffer = RingBuffer(capacity: capacity)
    gpuBuffer = RingBuffer(capacity: capacity)
    batteryBuffer = RingBuffer(capacity: capacity)
    temperatureBuffer = RingBuffer(capacity: capacity)
    systemPowerBuffer = RingBuffer(capacity: capacity)
    batteryPowerBuffer = RingBuffer(capacity: capacity)
    adapterInputPowerBuffer = RingBuffer(capacity: capacity)
  }

  deinit {
    samplingTask?.cancel()
  }

  func start() {
    start(resetBeforeSampling: false)
  }

  func stop() {
    samplingTask?.cancel()
    samplingTask = nil
    isRunning = false
  }

  func setSamplingInterval(_ interval: TimeInterval) {
    let normalized = SamplingIntervalPolicy.normalized(interval)
    guard normalized != configuredInterval else { return }
    configuredInterval = normalized
    resizeHistoryBuffers(to: SamplingIntervalPolicy.historyCapacity(for: normalized))
  }

  func handleSleep() {
    stop()
    appendDiscontinuity()
    objectWillChange.send()
  }

  func handleWake() {
    start(resetBeforeSampling: true)
  }

  private var currentInterval: TimeInterval {
    configuredInterval
  }

  private func start(resetBeforeSampling: Bool) {
    guard samplingTask == nil else { return }
    isRunning = true
    let sampler = self.sampler
    samplingTask = Task { [weak self, sampler] in
      if resetBeforeSampling {
        await sampler.resetForDiscontinuity()
      }

      while !Task.isCancelled {
        let result = await sampler.sample()
        let interval: TimeInterval
        do {
          guard !Task.isCancelled, let self else { break }
          interval = self.currentInterval
          self.consume(result, configuredInterval: interval)
        }

        let nanos = SamplingIntervalPolicy.sleepNanoseconds(
          intervalSeconds: interval,
          elapsedMilliseconds: result.timings.totalMilliseconds)
        if nanos > 0 {
          do {
            try await Task.sleep(nanoseconds: nanos)
          } catch {
            break
          }
        } else {
          await Task.yield()
        }
      }
    }
  }

  private func consume(_ result: SampleResult, configuredInterval: TimeInterval) {
    let newSnapshot = result.snapshot
    snapshot = newSnapshot
    samplingHealth = SamplingHealth(
      timings: result.timings,
      configuredIntervalSeconds: configuredInterval)
    onSnapshot?(newSnapshot)

    let historyPoints = SnapshotHistoryPoints.make(from: newSnapshot)
    cpuBuffer.append(historyPoints.cpu)
    memoryBuffer.append(historyPoints.memory)
    gpuBuffer.append(historyPoints.gpu)
    batteryBuffer.append(historyPoints.battery)
    temperatureBuffer.append(historyPoints.temperature)
    systemPowerBuffer.append(historyPoints.systemPower)
    batteryPowerBuffer.append(historyPoints.batteryPower)
    adapterInputPowerBuffer.append(historyPoints.adapterInputPower)
    appendTemperatureSensorHistory(from: newSnapshot)
    appendFanHistory(from: newSnapshot)
  }

  private func appendTemperatureSensorHistory(from snapshot: SystemSnapshot) {
    let sensors = snapshot.temperature.value?.sensors ?? []
    let observedIDs = Set(sensors.map(\.id))

    for sensor in sensors {
      temperatureSensorBuffers[
        sensor.id,
        default: RingBuffer<TimedPoint>(capacity: historyCapacity)
      ].append(TimedPoint(timestamp: snapshot.timestamp, value: sensor.celsius))
    }

    let missingIDs = temperatureSensorBuffers.keys.filter { !observedIDs.contains($0) }
    for id in missingIDs {
      temperatureSensorBuffers[
        id,
        default: RingBuffer<TimedPoint>(capacity: historyCapacity)
      ].append(TimedPoint(timestamp: snapshot.timestamp, value: nil))
    }
  }

  private func appendFanHistory(from snapshot: SystemSnapshot) {
    let fans = snapshot.fans.value?.fans ?? []
    let observedIndexes = Set(fans.map(\.index))

    for fan in fans {
      fanBuffers[
        fan.index,
        default: RingBuffer<TimedPoint>(capacity: historyCapacity)
      ].append(TimedPoint(timestamp: snapshot.timestamp, value: fan.currentRPM))
    }

    let missingIndexes = fanBuffers.keys.filter { !observedIndexes.contains($0) }
    for index in missingIndexes {
      fanBuffers[
        index,
        default: RingBuffer<TimedPoint>(capacity: historyCapacity)
      ].append(TimedPoint(timestamp: snapshot.timestamp, value: nil))
    }
  }

  private func appendDiscontinuity() {
    let point = TimedPoint(value: nil, discontinuity: true)
    cpuBuffer.append(point)
    memoryBuffer.append(point)
    gpuBuffer.append(point)
    batteryBuffer.append(point)
    temperatureBuffer.append(point)
    systemPowerBuffer.append(point)
    batteryPowerBuffer.append(point)
    adapterInputPowerBuffer.append(point)

    for id in Array(temperatureSensorBuffers.keys) {
      temperatureSensorBuffers[
        id,
        default: RingBuffer<TimedPoint>(capacity: historyCapacity)
      ].append(TimedPoint(value: nil, discontinuity: true))
    }

    for index in Array(fanBuffers.keys) {
      fanBuffers[
        index,
        default: RingBuffer<TimedPoint>(capacity: historyCapacity)
      ].append(TimedPoint(value: nil, discontinuity: true))
    }
  }

  private func resizeHistoryBuffers(to requestedCapacity: Int) {
    let nextCapacity = max(1, requestedCapacity)
    guard nextCapacity != historyCapacity else { return }
    historyCapacity = nextCapacity

    cpuBuffer.resize(to: nextCapacity)
    memoryBuffer.resize(to: nextCapacity)
    gpuBuffer.resize(to: nextCapacity)
    batteryBuffer.resize(to: nextCapacity)
    temperatureBuffer.resize(to: nextCapacity)
    systemPowerBuffer.resize(to: nextCapacity)
    batteryPowerBuffer.resize(to: nextCapacity)
    adapterInputPowerBuffer.resize(to: nextCapacity)

    for id in Array(temperatureSensorBuffers.keys) {
      temperatureSensorBuffers[
        id,
        default: RingBuffer<TimedPoint>(capacity: nextCapacity)
      ].resize(to: nextCapacity)
    }
    for index in Array(fanBuffers.keys) {
      fanBuffers[
        index,
        default: RingBuffer<TimedPoint>(capacity: nextCapacity)
      ].resize(to: nextCapacity)
    }
  }
}
