import Darwin
import XCTest

@testable import MacVitals

final class ProcessNameReusePolicyTests: XCTestCase {
  func testReusesNameForMatchingStableProcessIdentity() {
    let previous = sample(pid: 42, startTime: 900, name: "WindowServer")

    XCTAssertEqual(
      ProcessNameReusePolicy.reusableName(
        previous: previous,
        pid: 42,
        startTime: 900,
        unknownName: "Unknown process"),
      "WindowServer")
  }

  func testDoesNotReuseNameWhenStartTimeIsUnavailable() {
    XCTAssertNil(
      ProcessNameReusePolicy.reusableName(
        previous: sample(pid: 42, startTime: 0, name: "old"),
        pid: 42,
        startTime: 0,
        unknownName: "Unknown process"))
  }

  func testDoesNotReuseNameAcrossPIDReuse() {
    let previous = sample(pid: 42, startTime: 900, name: "old")

    XCTAssertNil(
      ProcessNameReusePolicy.reusableName(
        previous: previous,
        pid: 42,
        startTime: 901,
        unknownName: "Unknown process"))
  }

  func testDoesNotCacheTransientUnknownName() {
    let previous = sample(pid: 42, startTime: 900, name: "Unknown process")

    XCTAssertNil(
      ProcessNameReusePolicy.reusableName(
        previous: previous,
        pid: 42,
        startTime: 900,
        unknownName: "Unknown process"))
  }

  func testDoesNotReuseDifferentPID() {
    let previous = sample(pid: 41, startTime: 900, name: "other")

    XCTAssertNil(
      ProcessNameReusePolicy.reusableName(
        previous: previous,
        pid: 42,
        startTime: 900,
        unknownName: "Unknown process"))
  }

  private func sample(pid: pid_t, startTime: UInt64, name: String) -> ProcessCounterSample {
    ProcessCounterSample(
      pid: pid,
      parentPID: 1,
      startTime: startTime,
      name: name,
      cpuTimeNanoseconds: 0,
      physicalFootprintBytes: 0,
      energyNanojoules: nil,
      diskReadBytes: nil,
      diskWriteBytes: nil)
  }
}
