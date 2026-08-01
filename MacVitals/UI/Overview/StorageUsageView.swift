import Combine
import Foundation
import SwiftUI

nonisolated struct StorageUsageSnapshot: Sendable, Equatable {
  let volumeName: String
  let totalBytes: UInt64
  let usedBytes: UInt64
  let availableBytes: UInt64
  let usedFraction: Double
}

nonisolated enum StorageUsageReader {
  static func readHomeVolume() -> StorageUsageSnapshot? {
    let homePath = NSHomeDirectory()
    guard
      let attributes = try? FileManager.default.attributesOfFileSystem(forPath: homePath),
      let totalNumber = attributes[.systemSize] as? NSNumber,
      let freeNumber = attributes[.systemFreeSize] as? NSNumber
    else {
      return nil
    }

    let totalBytes = totalNumber.uint64Value
    guard totalBytes > 0 else { return nil }

    let availableBytes = min(totalBytes, freeNumber.uint64Value)
    let usedBytes = totalBytes - availableBytes
    let fraction = min(1, max(0, Double(usedBytes) / Double(totalBytes)))

    let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
    let resourceValues = try? homeURL.resourceValues(forKeys: [.volumeNameKey])
    let volumeName = resourceValues?.volumeName?.trimmingCharacters(in: .whitespacesAndNewlines)

    return StorageUsageSnapshot(
      volumeName: volumeName?.isEmpty == false ? volumeName! : "/",
      totalBytes: totalBytes,
      usedBytes: usedBytes,
      availableBytes: availableBytes,
      usedFraction: fraction)
  }
}

@MainActor
final class StorageUsageMonitor: ObservableObject {
  @Published private(set) var snapshot: StorageUsageSnapshot?
  @Published private(set) var isAvailable = true

  private var samplingTask: Task<Void, Never>?

  func start(interval: TimeInterval) {
    guard samplingTask == nil else { return }
    let normalizedInterval = max(5, interval.isFinite ? interval : 5)
    sample()
    samplingTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(normalizedInterval * 1_000_000_000))
        guard !Task.isCancelled, let self else { return }
        sample()
      }
    }
  }

  func restart(interval: TimeInterval) {
    stop()
    start(interval: interval)
  }

  func stop() {
    samplingTask?.cancel()
    samplingTask = nil
  }

  private func sample() {
    snapshot = StorageUsageReader.readHomeVolume()
    isAvailable = snapshot != nil
  }
}

struct StorageUsageView: View {
  @Environment(\.appTheme) private var theme
  @EnvironmentObject private var settings: SettingsStore
  @StateObject private var monitor = StorageUsageMonitor()

  var body: some View {
    let color = theme.color(for: .memory)
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label(StorageL10n.string("Storage"), systemImage: "internaldrive.fill")
          .font(.caption.bold())
          .foregroundStyle(color)
        Spacer()
        Text(monitor.snapshot?.volumeName ?? "—")
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if let snapshot = monitor.snapshot {
        ProgressView(value: snapshot.usedFraction)
          .tint(color)
          .accessibilityLabel(StorageL10n.string("Used"))
          .accessibilityValue(StorageByteFormatter.percentage(snapshot.usedFraction))

        HStack(alignment: .firstTextBaseline, spacing: 10) {
          storageValue(
            title: StorageL10n.string("Used"),
            value: StorageByteFormatter.bytes(snapshot.usedBytes))
          Spacer(minLength: 4)
          Text("\(StorageL10n.string("Total")) \(StorageByteFormatter.bytes(snapshot.totalBytes))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
          Spacer(minLength: 4)
          storageValue(
            title: StorageL10n.string("Available"),
            value: StorageByteFormatter.bytes(snapshot.availableBytes),
            alignment: .trailing)
        }
      } else {
        Text(StorageL10n.string("Storage data unavailable"))
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
      }
    }
    .padding(10)
    .background(
      color.opacity(theme.style == .multicolor ? 0.08 : 0.055),
      in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .stroke(Color.secondary.opacity(0.16), lineWidth: 1))
    .accessibilityElement(children: .contain)
    .onAppear { monitor.start(interval: settings.samplingInterval) }
    .onDisappear { monitor.stop() }
    .onChange(of: settings.samplingInterval) { interval in
      monitor.restart(interval: interval)
    }
  }

  private func storageValue(
    title: String,
    value: String,
    alignment: HorizontalAlignment = .leading
  ) -> some View {
    VStack(alignment: alignment, spacing: 1) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption.bold().monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
  }
}

nonisolated enum StorageByteFormatter {
  static func bytes(_ value: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useGB, .useTB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: Int64(clamping: value))
  }

  static func percentage(_ fraction: Double) -> String {
    guard fraction.isFinite else { return "—" }
    return String(format: "%.0f%%", min(1, max(0, fraction)) * 100)
  }
}
