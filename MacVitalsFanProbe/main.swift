import Darwin
import Foundation

#if !arch(arm64)
  #error("MacVitalsFanProbe supports Apple Silicon arm64 only")
#endif

private struct FanProbeDocument: Codable, Sendable {
  let schemaVersion: Int
  let recordedAt: Date
  let architecture: String
  let source: MetricSource
  let availability: MetricAvailability
  let quality: MeasurementQuality
  let unit: MetricUnit
  let fanCount: Int
  let fans: [FanReading]
  let message: String
}

private func emit(_ document: FanProbeDocument) throws {
  let encoder = JSONEncoder()
  encoder.dateEncodingStrategy = .iso8601
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  let data = try encoder.encode(document)
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data("\n".utf8))
}

private let sample = FanProvider().sample()
private let fans = sample.value?.fans ?? []
private let document = FanProbeDocument(
  schemaVersion: 1,
  recordedAt: sample.timestamp,
  architecture: "arm64",
  source: sample.source,
  availability: sample.availability,
  quality: sample.quality,
  unit: sample.unit,
  fanCount: fans.count,
  fans: fans,
  message: sample.message ?? "")

do {
  try emit(document)
} catch {
  FileHandle.standardError.write(Data("Could not encode fan evidence: \(error.localizedDescription)\n".utf8))
  exit(EX_SOFTWARE)
}

exit(sample.availability == .available && !fans.isEmpty ? EX_OK : EX_UNAVAILABLE)
