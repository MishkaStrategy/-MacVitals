import Combine
import Darwin
import SwiftUI

nonisolated struct NetworkTrafficSnapshot: Sendable, Equatable {
  let interfaceName: String
  let receivedBytes: UInt64
  let sentBytes: UInt64
  let sessionReceivedBytes: UInt64
  let sessionSentBytes: UInt64
  let downloadBytesPerSecond: Double?
  let uploadBytesPerSecond: Double?
}

nonisolated struct NetworkTrafficHistorySample: Sendable, Equatable, Identifiable {
  let id: UUID
  let timestamp: Date
  let downloadBytesPerSecond: Double
  let uploadBytesPerSecond: Double
}

nonisolated struct NetworkInterfaceCounters: Sendable, Equatable {
  let name: String
  let receivedBytes: UInt64
  let sentBytes: UInt64
}

nonisolated enum NetworkInterfaceReader {
  static func preferredActiveInterface() -> NetworkInterfaceCounters? {
    var firstAddress: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&firstAddress) == 0, let firstAddress else { return nil }
    defer { freeifaddrs(firstAddress) }

    var candidates: [NetworkInterfaceCounters] = []
    var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
    while let pointer = cursor {
      let interface = pointer.pointee
      cursor = interface.ifa_next

      let flags = Int32(bitPattern: interface.ifa_flags)
      guard (flags & IFF_UP) != 0,
        (flags & IFF_RUNNING) != 0,
        (flags & IFF_LOOPBACK) == 0,
        let address = interface.ifa_addr,
        Int32(address.pointee.sa_family) == AF_LINK,
        let rawData = interface.ifa_data,
        let namePointer = interface.ifa_name
      else { continue }

      let name = String(cString: namePointer)
      guard !name.hasPrefix("lo"), !name.hasPrefix("awdl"), !name.hasPrefix("llw") else {
        continue
      }

      let data = rawData.assumingMemoryBound(to: if_data.self).pointee
      candidates.append(
        NetworkInterfaceCounters(
          name: name,
          receivedBytes: UInt64(data.ifi_ibytes),
          sentBytes: UInt64(data.ifi_obytes)))
    }

    return candidates.max { lhs, rhs in
      let lhsTotal = lhs.receivedBytes &+ lhs.sentBytes
      let rhsTotal = rhs.receivedBytes &+ rhs.sentBytes
      if lhsTotal == rhsTotal { return lhs.name > rhs.name }
      return lhsTotal < rhsTotal
    }
  }
}

@MainActor
final class NetworkTrafficMonitor: ObservableObject {
  private struct Baseline {
    let counters: NetworkInterfaceCounters
    let timestamp: Date
  }

  @Published private(set) var snapshot: NetworkTrafficSnapshot?
  @Published private(set) var history: [NetworkTrafficHistorySample] = []
  @Published private(set) var isAvailable = true

  private var baseline: Baseline?
  private var sessionBaseline: NetworkInterfaceCounters?
  private var samplingTask: Task<Void, Never>?
  private var activeConsumers = 0
  private var currentInterval: TimeInterval = 5

  func start(interval: TimeInterval) {
    activeConsumers += 1
    currentInterval = normalized(interval)
    guard samplingTask == nil else { return }
    runSamplingTask()
  }

  func restart(interval: TimeInterval) {
    currentInterval = normalized(interval)
    guard activeConsumers > 0 else { return }
    samplingTask?.cancel()
    samplingTask = nil
    runSamplingTask()
  }

  func stop() {
    activeConsumers = max(0, activeConsumers - 1)
    guard activeConsumers == 0 else { return }
    samplingTask?.cancel()
    samplingTask = nil
    baseline = nil
  }

  private func normalized(_ interval: TimeInterval) -> TimeInterval {
    max(1, interval.isFinite ? interval : 5)
  }

  private func runSamplingTask() {
    sample(now: Date())
    let interval = currentInterval
    samplingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        guard !Task.isCancelled, let self else { return }
        sample(now: Date())
      }
    }
  }

  private func sample(now: Date) {
    guard let counters = NetworkInterfaceReader.preferredActiveInterface() else {
      isAvailable = false
      snapshot = nil
      baseline = nil
      sessionBaseline = nil
      return
    }

    if sessionBaseline?.name != counters.name
      || counters.receivedBytes < (sessionBaseline?.receivedBytes ?? 0)
      || counters.sentBytes < (sessionBaseline?.sentBytes ?? 0)
    {
      sessionBaseline = counters
    }

    var downloadRate: Double?
    var uploadRate: Double?
    if let baseline,
      baseline.counters.name == counters.name,
      counters.receivedBytes >= baseline.counters.receivedBytes,
      counters.sentBytes >= baseline.counters.sentBytes
    {
      let elapsed = now.timeIntervalSince(baseline.timestamp)
      if elapsed.isFinite, elapsed > 0.05 {
        downloadRate = Double(counters.receivedBytes - baseline.counters.receivedBytes) / elapsed
        uploadRate = Double(counters.sentBytes - baseline.counters.sentBytes) / elapsed
      }
    }

    let sessionReceived = counters.receivedBytes - (sessionBaseline?.receivedBytes ?? counters.receivedBytes)
    let sessionSent = counters.sentBytes - (sessionBaseline?.sentBytes ?? counters.sentBytes)

    isAvailable = true
    snapshot = NetworkTrafficSnapshot(
      interfaceName: counters.name,
      receivedBytes: counters.receivedBytes,
      sentBytes: counters.sentBytes,
      sessionReceivedBytes: sessionReceived,
      sessionSentBytes: sessionSent,
      downloadBytesPerSecond: downloadRate,
      uploadBytesPerSecond: uploadRate)
    baseline = Baseline(counters: counters, timestamp: now)

    if downloadRate != nil || uploadRate != nil {
      history.append(
        NetworkTrafficHistorySample(
          id: UUID(),
          timestamp: now,
          downloadBytesPerSecond: max(0, downloadRate ?? 0),
          uploadBytesPerSecond: max(0, uploadRate ?? 0)))
      let cutoff = now.addingTimeInterval(-60 * 60)
      history.removeAll { $0.timestamp < cutoff }
    }
  }
}

@MainActor
struct NetworkTrafficView: View {
  @Environment(\.appTheme) private var theme
  @EnvironmentObject private var settings: SettingsStore
  @ObservedObject private var monitor: NetworkTrafficMonitor

  private let action: () -> Void

  init(
    monitor: NetworkTrafficMonitor = NetworkTrafficMonitor(),
    action: @escaping () -> Void = {}
  ) {
    _monitor = ObservedObject(wrappedValue: monitor)
    self.action = action
  }

  var body: some View {
    let color = theme.color(for: .fans)
    Button(action: action) {
      VStack(alignment: .leading, spacing: 9) {
        HStack {
          Label(NetworkL10n.string("Network"), systemImage: "network")
            .font(.caption.bold())
            .foregroundStyle(color)
          Spacer()
          Text(monitor.snapshot?.interfaceName ?? "—")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
          Image(systemName: "chevron.right")
            .font(.caption.bold())
            .foregroundStyle(.tertiary)
        }

        if let snapshot = monitor.snapshot {
          HStack(spacing: 12) {
            speedValue(
              title: NetworkL10n.string("Download"),
              symbol: "arrow.down",
              value: snapshot.downloadBytesPerSecond,
              color: color)
            Divider().frame(height: 31)
            speedValue(
              title: NetworkL10n.string("Upload"),
              symbol: "arrow.up",
              value: snapshot.uploadBytesPerSecond,
              color: color)
          }
          Text(
            "\(NetworkL10n.string("Received")) \(NetworkByteFormatter.bytes(snapshot.receivedBytes)) · "
              + "\(NetworkL10n.string("Sent")) \(NetworkByteFormatter.bytes(snapshot.sentBytes))"
          )
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
        } else {
          Text(NetworkL10n.string("Network data unavailable"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        }
      }
      .padding(10)
      .background(
        color.opacity(theme.style == .multicolor ? 0.08 : 0.055),
        in: RoundedRectangle(cornerRadius: 11))
      .overlay(
        RoundedRectangle(cornerRadius: 11)
          .stroke(Color.secondary.opacity(0.16), lineWidth: 1))
      .contentShape(RoundedRectangle(cornerRadius: 11))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityHint(NetworkL10n.string("Open traffic history"))
    .onAppear { monitor.start(interval: settings.samplingInterval) }
    .onDisappear { monitor.stop() }
    .onChange(of: settings.samplingInterval) { interval in
      monitor.restart(interval: interval)
    }
  }

  private func speedValue(
    title: String,
    symbol: String,
    value: Double?,
    color: Color
  ) -> some View {
    HStack(spacing: 7) {
      Image(systemName: symbol)
        .foregroundStyle(color)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.caption2)
          .foregroundStyle(.secondary)
        Text(NetworkByteFormatter.rate(value))
          .font(.headline.monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
  }
}

nonisolated enum NetworkByteFormatter {
  static func bytes(_ value: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
    return formatter.string(fromByteCount: Int64(clamping: value))
  }

  static func rate(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return L10n.string("Collecting data") }
    let bounded = min(Double(UInt64.max), value.rounded())
    return "\(bytes(UInt64(bounded)))/s"
  }
}
