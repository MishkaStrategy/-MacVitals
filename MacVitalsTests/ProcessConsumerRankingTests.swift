import Darwin
import XCTest

@testable import MacVitals

final class ProcessConsumerRankingTests: XCTestCase {
  func testRankingFiltersIdleApplicationsAndUsesStableNameTieBreak() {
    let idle = usage(id: "idle", name: "Idle", pid: 1)
    let zulu = usage(id: "z", name: "Zulu", pid: 2, cpu: 8)
    let alpha = usage(id: "a", name: "alpha", pid: 3, cpu: 8)

    let ranked = ProcessConsumerRanking.topApplications(
      [idle, zulu, alpha],
      metric: .cpu)

    XCTAssertEqual(ranked.map(\.application.id), ["a", "z"])
    XCTAssertEqual(ranked.map(\.rank), [1, 2])
  }

  func testEnergyRankingUsesMeasuredWattsWhenAvailable() {
    let measured = usage(id: "measured", name: "Measured", pid: 4, energyWatts: 3, energy: 90)
    let estimated = usage(id: "estimated", name: "Estimated", pid: 5, energy: 20)

    let ranked = ProcessConsumerRanking.topApplications(
      [estimated, measured],
      metric: .energy)

    XCTAssertEqual(ranked.map(\.application.id), ["estimated", "measured"])
  }

  func testRankingHonorsLimitAndRepresentativePIDs() {
    let applications = (0..<15).map { index in
      usage(
        id: "app-\(index)",
        name: "App \(index)",
        pid: pid_t(100 + index),
        memory: UInt64(index + 2) * 1_048_576)
    }

    let ranked = ProcessConsumerRanking.topApplications(
      applications,
      metric: .memory,
      limit: 10)

    XCTAssertEqual(ranked.count, 10)
    XCTAssertEqual(ranked.first?.application.representativePID, 114)
    XCTAssertEqual(ranked.last?.application.representativePID, 105)
    XCTAssertEqual(ranked.map(\.rank), Array(1...10))
  }

  private func usage(
    id: String,
    name: String,
    pid: pid_t,
    cpu: Double = 0,
    memory: UInt64 = 0,
    energyWatts: Double? = nil,
    energy: Double = 0,
    gpu: Double = 0
  ) -> ApplicationProcessUsage {
    ApplicationProcessUsage(
      id: id,
      name: name,
      bundleIdentifier: nil,
      representativePID: pid,
      processCount: 1,
      cpuPercent: cpu,
      memoryBytes: memory,
      energyWatts: energyWatts,
      energyImpactScore: energy,
      gpuActivityScore: gpu,
      diskBytesPerSecond: 0,
      isGPUActivityEstimated: true,
      isEnergyEstimated: energyWatts == nil)
  }
}
