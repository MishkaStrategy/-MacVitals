import XCTest

@testable import MacVitals

final class FanProviderTests: XCTestCase {
  func testSingleFanSampleReadsRPMRangeAndMode() throws {
    let source = FakeFanSMC(values: [
      "FNum": ui8(1),
      "F0Ac": float(2_100),
      "F0Tg": float(2_300),
      "F0Mn": float(1_200),
      "F0Mx": float(6_000),
      "F0md": ui8(0),
    ])
    let result = FanProvider(factory: { source }).sample(now: fixedDate)
    let fan = try XCTUnwrap(result.value?.fans.first)

    XCTAssertEqual(result.availability, .available)
    XCTAssertEqual(result.source, .appleSMC)
    XCTAssertEqual(fan.index, 0)
    XCTAssertEqual(try XCTUnwrap(fan.currentRPM), 2_100, accuracy: 0.01)
    XCTAssertEqual(try XCTUnwrap(fan.targetRPM), 2_300, accuracy: 0.01)
    XCTAssertEqual(try XCTUnwrap(fan.minimumRPM), 1_200, accuracy: 0.01)
    XCTAssertEqual(try XCTUnwrap(fan.maximumRPM), 6_000, accuracy: 0.01)
    XCTAssertEqual(fan.mode, .automatic)
  }

  func testTwoFansSupportDifferentModeKeyCasing() throws {
    let source = FakeFanSMC(values: [
      "FNum": ui8(2),
      "F0Ac": float(1_900), "F0Mn": float(1_200), "F0Mx": float(5_800), "F0md": ui8(0),
      "F1Ac": float(2_000), "F1Mn": float(1_300), "F1Mx": float(5_900), "F1Md": ui8(1),
    ])
    let fans = try XCTUnwrap(FanProvider(factory: { source }).sample().value?.fans)

    XCTAssertEqual(fans.count, 2)
    XCTAssertEqual(fans[0].mode, .automatic)
    XCTAssertEqual(fans[1].mode, .manual)
  }

  func testZeroFansIsUnsupportedRatherThanProviderFailure() throws {
    let result = FanProvider(factory: { FakeFanSMC(values: ["FNum": ui8(0)]) }).sample()

    XCTAssertEqual(result.availability, .unsupported)
    XCTAssertEqual(try XCTUnwrap(result.value).fans, [])
  }

  func testInvalidFanCountFailsClosed() {
    for value in [9, 255] {
      let result = FanProvider(factory: {
        FakeFanSMC(values: ["FNum": ui8(UInt8(value))])
      }).sample()
      XCTAssertEqual(result.availability, .providerError)
      XCTAssertNil(result.value)
    }
  }

  func testPartialFanDataRetainsValidFan() throws {
    let source = FakeFanSMC(values: [
      "FNum": ui8(2),
      "F0Ac": float(2_100), "F0Mn": float(1_200), "F0Mx": float(6_000),
    ])
    let result = FanProvider(factory: { source }).sample()

    XCTAssertEqual(result.availability, .available)
    XCTAssertEqual(result.value?.fans.count, 1)
    XCTAssertNotNil(result.message)
  }

  func testNonFiniteCurrentRPMIsOmittedWithoutInventingZero() throws {
    let source = FakeFanSMC(values: [
      "FNum": ui8(1),
      "F0Ac": float(.nan),
      "F0Mn": float(1_200),
      "F0Mx": float(6_000),
    ])
    let fan = try XCTUnwrap(FanProvider(factory: { source }).sample().value?.fans.first)

    XCTAssertNil(fan.currentRPM)
    XCTAssertEqual(fan.minimumRPM, 1_200)
    XCTAssertEqual(fan.maximumRPM, 6_000)
  }

  func testReversedHardwareRangeRejectsFan() {
    let source = FakeFanSMC(values: [
      "FNum": ui8(1),
      "F0Ac": float(2_000),
      "F0Mn": float(6_000),
      "F0Mx": float(1_200),
    ])
    let result = FanProvider(factory: { source }).sample()

    XCTAssertEqual(result.availability, .temporarilyUnavailable)
    XCTAssertNil(result.value)
  }

  func testConnectionFailureReturnsProviderError() {
    let result = FanProvider(factory: {
      throw AppleSMCError.connectionFailed(kern_return_t(-1))
    }).sample()
    XCTAssertEqual(result.availability, .providerError)
    XCTAssertNil(result.value)
  }

  func testFloatRoundTripUsesNativeEndian() throws {
    let encoded = try XCTUnwrap(AppleSMCDataDecoder.bytes(for: 3_456.5, dataType: "flt ", size: 4))
    let decoded = try XCTUnwrap(
      AppleSMCDataDecoder.number(AppleSMCKeyValue(bytes: encoded, dataType: "flt ")))
    XCTAssertEqual(decoded, 3_456.5, accuracy: 0.01)
  }

  func testFPE2RoundTripUsesBigEndianFixedPoint() throws {
    let encoded = try XCTUnwrap(AppleSMCDataDecoder.bytes(for: 2_500, dataType: "fpe2", size: 2))
    XCTAssertEqual(encoded, [0x27, 0x10])
    let decoded = try XCTUnwrap(
      AppleSMCDataDecoder.number(AppleSMCKeyValue(bytes: encoded, dataType: "fpe2")))
    XCTAssertEqual(decoded, 2_500, accuracy: 0.01)
  }

  func testIntegerDecodersUseSMCBigEndianConvention() {
    XCTAssertEqual(AppleSMCDataDecoder.unsignedInteger(ui8(2)), 2)
    XCTAssertEqual(
      AppleSMCDataDecoder.unsignedInteger(.init(bytes: [0x12, 0x34], dataType: "ui16")),
      0x1234)
    XCTAssertEqual(
      AppleSMCDataDecoder.unsignedInteger(
        .init(bytes: [0x00, 0x01, 0x02, 0x03], dataType: "ui32")),
      0x0001_0203)
  }

  func testNormalizerRejectsImpossibleRPMAndFanIndexes() {
    for value in [Double.nan, .infinity, -1, 20_001] {
      XCTAssertNil(FanValueNormalizer.rpm(value))
    }
    XCTAssertNil(
      FanValueNormalizer.reading(
        index: 8, current: 2_000, target: nil, minimum: 1_000, maximum: 6_000,
        mode: .automatic))
  }

  private let fixedDate = Date(timeIntervalSince1970: 100)

  private func ui8(_ value: UInt8) -> AppleSMCKeyValue {
    AppleSMCKeyValue(bytes: [value], dataType: "ui8 ")
  }

  private func float(_ value: Float) -> AppleSMCKeyValue {
    var value = value
    let bytes = withUnsafeBytes(of: &value) { Array($0) }
    return AppleSMCKeyValue(bytes: bytes, dataType: "flt ")
  }
}

private final class FakeFanSMC: AppleSMCReading, @unchecked Sendable {
  private let values: [String: AppleSMCKeyValue]

  init(values: [String: AppleSMCKeyValue]) {
    self.values = values
  }

  func readKey(_ key: String) throws -> AppleSMCKeyValue {
    guard let value = values[key] else { throw AppleSMCError.firmware(0x84) }
    return value
  }
}
