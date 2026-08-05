import Foundation
import XCTest

@testable import MacVitals

final class ProviderTimingAppendWriterTests: XCTestCase {
  func testWriterAppendsMultipleJSONLines() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = root.appendingPathComponent("provider-timings.jsonl")
    defer { try? FileManager.default.removeItem(at: root) }

    do {
      let writer = try XCTUnwrap(ProviderTimingAppendWriter(url: url))
      writer.append(Data("{\"cycle\":1}".utf8))
      writer.append(Data("{\"cycle\":2}".utf8))
    }

    let lines = try String(contentsOf: url, encoding: .utf8)
      .split(separator: "\n")
      .map(String.init)
    XCTAssertEqual(lines, ["{\"cycle\":1}", "{\"cycle\":2}"])
  }

  func testWriterCreatesMissingParentDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = root.appendingPathComponent("nested/provider-timings.jsonl")
    defer { try? FileManager.default.removeItem(at: root) }

    do {
      let writer = try XCTUnwrap(ProviderTimingAppendWriter(url: url))
      writer.append(Data("{}".utf8))
    }

    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
  }
}
