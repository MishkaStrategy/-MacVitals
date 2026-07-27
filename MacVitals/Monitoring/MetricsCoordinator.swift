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
  @Published private(set) var cpuHistory: [TimedPoint] = []
  @Published private(set) var memoryHistory: [TimedPoint] = []
  @Published private(set) var gpuHistory: [TimedPoint] = []
  @Published private(set) var batteryHistory: [TimedPoint] = []
  @Published private(set) var temperatureHistory: [TimedPoint] = []
  @Published private(set) var temperatureSensorHistory: [String: [TimedPoint]] = [:]
  @Published private(set) var systemPowerHistory: [TimedPoint] = []
  @Published private(set) var batteryPowerHistory: [TimedPoint] = []
  @Published private(set) var adapterInputPowerHistory: [TimedPoint] = []
  @Published private(set) var fanHistory: [Int: [TimedPoint]] = [:]
  @Published private(set) var samplingHealth: SamplingHealth?
  @Published private(set) var isRunning = false

  var onSnapshot: ((SystemSnapshot) -> Void)?

  private static let maximumHistoryCapacity = 3_600
  private let sampler = SystemSampler()
  private var cpuBuffer = RingBuffer<TimedPoint>(capacity: maximumHistoryCapacity)
  private var memoryBuffer = RingBuffer<TimedPoint>(capacity: maximumHistoryCapacity)
  private var gpuBuffer = RingBuffer<TimedPoint>(capacity: maximumHistoryCapacity)
  private var batteryBuffer = RingBuffer<TimedPoint>(capacity: maximumHistoryCapacity)
  private var temperatureBuffer = RingBuffer<TimedPoint>(capacity: maximumHistoryCapacity)
  private var temperatureSensorBuffers: [String: RingBuffer<TimedPoint>] = [:]
  private var systemPowerBuffer = RingBuffer<TimedPoint>(capacity: maximumHistoryCapacity)
  private var batteryPowerBuffer = RingBuffer<TimedPoint>(capacity: maximumHistoryCapacity)
  private var adapterInputPowerBuffer = RingBuffer<TimedPoint>(capacity: maximumHistoryCapacity)
  private var fanBuffers: [Int: RingBuffer<TimedPoint>] = [:]
  private var samplingTask: Task<Void, Never>?

  func start() {
    start(resetBeforeSampling: false)
  }

  func stop() {
    samplingTask?.cancel()
    samplingTask = nil
    isRunning = false
  }

  func handleSleep() {
    stop()
    appendDiscontinuity()
    publishHistory()
  }

  func handleWake() {
    start(resetBeforeSampling: true)
  }

  private var currentInterval: TimeInterval {
    SamplingIntervalPolicy.normalized(
      UserDefaults.standard.double(forKey: "samplingInterval"))
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
        guard !Task.isCancelled else { break }

        let interval = self?.currentInterval ?? SamplingIntervalPolicy.defaultValue
        self?.consume(result, configuredInterval: interval)

        let nanos = SamplingIntervalPolicy.sleepNanoseconds(
          intervalSeconds: interval,
          elapsedMilliseconds: result.timings.totalMilliseconds)
        if nanos > 0 {
          try? await Task.sleep(nanoseconds: nanos)
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
    publishHistory()
  }

  private func appendTemperatureSensorHistory(from snapshot: SystemSnapshot) {
    let sensors = snapshot.temperature.value?.sensors ?? []
    let observedIDs = Set(sensors.map(\.id))

    for sensor in sensors {
      var buffer = temperatureSensorBuffers[sensor.id]
        ?? RingBuffer<TimedPoint>(capacity: Self.maximumHistoryCapacity)
      buffer.append(TimedPoint(timestamp: snapshot.timestamp, value: sensor.celsius))
      temperatureSensorBuffers[sensor.id] = buffer
    }

    for id in Array(temperatureSensorBuffers.keys) where !observedIDs.contains(id) {
      guard var buffer = temperatureSensorBuffers[id] else { continue }
      buffer.append(TimedPoint(timestamp: snapshot.timestamp, value: nil))
      temperatureSensorBuffers[id] = buffer
    }
  }

  private func appendFanHistory(from snapshot: SystemSnapshot) {
    let fans = snapshot.fans.value?.fans ?? []
    let observedIndexes = Set(fans.map(\.index))

    for fan in fans {
      var buffer = fanBuffers[fan.index]
        ?? RingBuffer<TimedPoint>(capacity: Self.maximumHistoryCapacity)
      buffer.append(TimedPoint(timestamp: snapshot.timestamp, value: fan.currentRPM))
      fanBuffers[fan.index] = buffer
    }

    for index in Array(fanBuffers.keys) where !observedIndexes.contains(index) {
      guard var buffer = fanBuffers[index] else { continue }
      buffer.append(TimedPoint(timestamp: snapshot.timestamp, value: nil))
      fanBuffers[index] = buffer
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
      guard var buffer = temperatureSensorBuffers[id] else { continue }
      buffer.append(TimedPoint(value: nil, discontinuity: true))
      temperatureSensorBuffers[id] = buffer
    }

    for index in Array(fanBuffers.keys) {
      guard var buffer = fanBuffers[index] else { continue }
      buffer.append(TimedPoint(value: nil, discontinuity: true))
      fanBuffers[index] = buffer
    }
  }

  private func publishHistory() {
    cpuHistory = cpuBuffer.values
    memoryHistory = memoryBuffer.values
    gpuHistory = gpuBuffer.values
    batteryHistory = batteryBuffer.values
    temperatureHistory = temperatureBuffer.values
    temperatureSensorHistory = temperatureSensorBuffers.mapValues(\.values)
    systemPowerHistory = systemPowerBuffer.values
    batteryPowerHistory = batteryPowerBuffer.values
    adapterInputPowerHistory = adapterInputPowerBuffer.values
    fanHistory = fanBuffers.mapValues(\.values)
  }
}
