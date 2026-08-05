import XCTest

@testable import MacVitals

final class AppleSMCKeyMetadataCacheTests: XCTestCase {
  func testRepeatedKeyUsesOneMetadataLoad() throws {
    let cache = AppleSMCKeyMetadataCache()
    var loadCount = 0

    let first = try cache.value(for: 0x4630_4163) {
      loadCount += 1
      return AppleSMCKeyMetadata(dataSize: 2, dataType: 0x6670_6532)
    }
    let second = try cache.value(for: 0x4630_4163) {
      loadCount += 1
      return AppleSMCKeyMetadata(dataSize: 4, dataType: 0x666C_7420)
    }

    XCTAssertEqual(first, AppleSMCKeyMetadata(dataSize: 2, dataType: 0x6670_6532))
    XCTAssertEqual(second, first)
    XCTAssertEqual(loadCount, 1)
    XCTAssertEqual(cache.count, 1)
  }

  func testDifferentKeysLoadIndependently() throws {
    let cache = AppleSMCKeyMetadataCache()
    var loadCount = 0

    _ = try cache.value(for: 1) {
      loadCount += 1
      return AppleSMCKeyMetadata(dataSize: 1, dataType: 10)
    }
    _ = try cache.value(for: 2) {
      loadCount += 1
      return AppleSMCKeyMetadata(dataSize: 2, dataType: 20)
    }

    XCTAssertEqual(loadCount, 2)
    XCTAssertEqual(cache.count, 2)
  }

  func testFailedLoadIsNotCached() throws {
    enum ExpectedFailure: Error { case failed }

    let cache = AppleSMCKeyMetadataCache()
    var loadCount = 0

    XCTAssertThrowsError(
      try cache.value(for: 1) {
        loadCount += 1
        throw ExpectedFailure.failed
      })

    let metadata = try cache.value(for: 1) {
      loadCount += 1
      return AppleSMCKeyMetadata(dataSize: 4, dataType: 30)
    }

    XCTAssertEqual(metadata, AppleSMCKeyMetadata(dataSize: 4, dataType: 30))
    XCTAssertEqual(loadCount, 2)
    XCTAssertEqual(cache.count, 1)
  }
}
