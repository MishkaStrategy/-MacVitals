import Darwin.Mach
import Foundation
import XCTest

@testable import MacVitals

final class MachHostPortLeaseTests: XCTestCase {
  func testLeaseAcquiresAndReleasesExactlyOnce() {
    let recorder = PortLifecycleRecorder()
    let expectedPort = host_t(42)
    var lease: MachHostPortLease? = MachHostPortLease(
      acquire: {
        recorder.recordAcquire()
        return expectedPort
      },
      release: { name in
        recorder.recordRelease(name)
      })

    XCTAssertEqual(lease?.name, expectedPort)
    XCTAssertEqual(recorder.acquireCount, 1)
    XCTAssertEqual(recorder.releasedNames, [])

    lease = nil

    XCTAssertEqual(recorder.acquireCount, 1)
    XCTAssertEqual(recorder.releasedNames, [expectedPort])
  }

  func testNullPortIsNotReleased() {
    let recorder = PortLifecycleRecorder()
    var lease: MachHostPortLease? = MachHostPortLease(
      acquire: { MACH_PORT_NULL },
      release: { name in recorder.recordRelease(name) })

    XCTAssertEqual(lease?.name, MACH_PORT_NULL)
    lease = nil

    XCTAssertEqual(recorder.releasedNames, [])
  }

  func testSharedLeaseHasStableIdentity() {
    XCTAssertTrue(MachHostPortLease.shared === MachHostPortLease.shared)
  }
}

private final class PortLifecycleRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var acquisitions = 0
  private var releases: [host_t] = []

  var acquireCount: Int {
    lock.withLock { acquisitions }
  }

  var releasedNames: [host_t] {
    lock.withLock { releases }
  }

  func recordAcquire() {
    lock.withLock { acquisitions += 1 }
  }

  func recordRelease(_ name: host_t) {
    lock.withLock { releases.append(name) }
  }
}
