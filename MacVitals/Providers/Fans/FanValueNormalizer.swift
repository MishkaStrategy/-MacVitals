import Foundation

nonisolated enum AppleSMCDataDecoder {
  static func number(_ value: AppleSMCKeyValue) -> Double? {
    let bytes = value.bytes
    let decoded: Double?
    switch value.dataType {
    case "flt ":
      guard bytes.count >= 4 else { return nil }
      let bits = bytes.prefix(4).enumerated().reduce(UInt32(0)) { partial, entry in
        partial | (UInt32(entry.element) << UInt32(entry.offset * 8))
      }
      decoded = Double(Float(bitPattern: bits))
    case "fpe2":
      guard bytes.count >= 2 else { return nil }
      let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
      decoded = Double(raw) / 4
    case "sp78":
      guard bytes.count >= 2 else { return nil }
      let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
      decoded = Double(raw) / 256
    case "ui8 ", "ui8":
      guard let first = bytes.first else { return nil }
      decoded = Double(first)
    case "ui16":
      guard bytes.count >= 2 else { return nil }
      decoded = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
    case "ui32":
      guard bytes.count >= 4 else { return nil }
      decoded = Double(
        UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8
          | UInt32(bytes[3]))
    default:
      if bytes.count == 4 {
        let bits = bytes.enumerated().reduce(UInt32(0)) { partial, entry in
          partial | (UInt32(entry.element) << UInt32(entry.offset * 8))
        }
        decoded = Double(Float(bitPattern: bits))
      } else if bytes.count == 2 {
        decoded = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
      } else {
        decoded = bytes.first.map(Double.init)
      }
    }
    guard let decoded, decoded.isFinite else { return nil }
    return decoded
  }

  static func unsignedInteger(_ value: AppleSMCKeyValue) -> Int? {
    guard let number = number(value), number.isFinite, number >= 0,
      number <= Double(Int.max)
    else { return nil }
    return Int(number.rounded(.towardZero))
  }

  static func bytes(for number: Double, dataType: String, size: Int) -> [UInt8]? {
    guard number.isFinite, size > 0, size <= 32 else { return nil }
    switch dataType {
    case "flt ":
      guard size == 4 else { return nil }
      let bits = Float(number).bitPattern
      return [
        UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF),
        UInt8((bits >> 16) & 0xFF), UInt8((bits >> 24) & 0xFF),
      ]
    case "fpe2":
      guard size == 2, number >= 0, number <= Double(UInt16.max) / 4 else { return nil }
      let raw = UInt16((number * 4).rounded())
      return [UInt8((raw >> 8) & 0xFF), UInt8(raw & 0xFF)]
    default:
      guard size == 4 else { return nil }
      let bits = Float(number).bitPattern
      return [
        UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF),
        UInt8((bits >> 16) & 0xFF), UInt8((bits >> 24) & 0xFF),
      ]
    }
  }
}

nonisolated enum FanValueNormalizer {
  static let maximumFanCount = 8
  static let plausibleRPMRange = 0.0...20_000.0

  static func fanCount(_ value: Int?) -> Int? {
    guard let value, (0...maximumFanCount).contains(value) else { return nil }
    return value
  }

  static func rpm(_ value: Double?) -> Double? {
    guard let value, value.isFinite, plausibleRPMRange.contains(value) else { return nil }
    return value
  }

  static func reading(
    index: Int,
    current: Double?,
    target: Double?,
    minimum: Double?,
    maximum: Double?,
    mode: FanMode
  ) -> FanReading? {
    guard index >= 0, index < maximumFanCount else { return nil }
    let current = rpm(current)
    let target = rpm(target)
    let minimum = rpm(minimum)
    let maximum = rpm(maximum)
    if let minimum, let maximum, minimum > maximum { return nil }
    guard current != nil || target != nil || minimum != nil || maximum != nil else { return nil }
    return FanReading(
      index: index,
      currentRPM: current,
      targetRPM: target,
      minimumRPM: minimum,
      maximumRPM: maximum,
      mode: mode)
  }
}
