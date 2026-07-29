import Foundation
import IOKit

nonisolated enum AppleSMCCommand: UInt8 {
  case kernelIndex = 2
  case readBytes = 5
  case writeBytes = 6
  case getKeyFromIndex = 8
  case readKeyInfo = 9
}

nonisolated enum AppleSMCError: LocalizedError, Sendable {
  case connectionFailed(kern_return_t)
  case invalidKey
  case invalidPayload
  case ioKit(kern_return_t)
  case firmware(UInt8)

  var errorDescription: String? {
    switch self {
    case .connectionFailed(let code):
      return "Could not open AppleSMC (0x\(String(code, radix: 16)))"
    case .invalidKey:
      return "SMC keys must contain exactly four ASCII characters"
    case .invalidPayload:
      return "SMC returned an invalid payload"
    case .ioKit(let code):
      return "AppleSMC IOKit call failed (0x\(String(code, radix: 16)))"
    case .firmware(let code):
      return "AppleSMC firmware rejected the request (0x\(String(code, radix: 16)))"
    }
  }
}

nonisolated struct AppleSMCKeyValue: Sendable, Equatable {
  let bytes: [UInt8]
  let dataType: String
}

nonisolated protocol AppleSMCReading: Sendable {
  func readKey(_ key: String) throws -> AppleSMCKeyValue
}

nonisolated protocol AppleSMCWriting: AppleSMCReading {
  func writeKey(_ key: String, bytes: [UInt8]) throws
}

nonisolated final class AppleSMCConnection: AppleSMCWriting, @unchecked Sendable {
  private let connection: io_connect_t
  private let lock = NSLock()

  init() throws {
    guard let matching = IOServiceMatching("AppleSMC") else {
      throw AppleSMCError.connectionFailed(KERN_FAILURE)
    }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard service != 0 else {
      throw AppleSMCError.connectionFailed(KERN_FAILURE)
    }
    defer { IOObjectRelease(service) }

    var opened: io_connect_t = 0
    let result = IOServiceOpen(service, mach_task_self_, 0, &opened)
    guard result == kIOReturnSuccess else {
      throw AppleSMCError.connectionFailed(result)
    }
    connection = opened
  }

  deinit {
    IOServiceClose(connection)
  }

  func readKey(_ key: String) throws -> AppleSMCKeyValue {
    try lock.withLock {
      try readKeyLocked(key)
    }
  }

  func keyNames(maximumCount: Int = 2_048) throws -> [String] {
    guard maximumCount > 0 else { return [] }
    return try lock.withLock {
      let countValue = try readKeyLocked("#KEY")
      guard let decodedCount = AppleSMCDataDecoder.unsignedInteger(countValue), decodedCount >= 0 else {
        throw AppleSMCError.invalidPayload
      }

      let count = min(decodedCount, maximumCount)
      var names: [String] = []
      names.reserveCapacity(count)
      for index in 0..<count {
        var input = AppleSMCParam()
        input.data8 = AppleSMCCommand.getKeyFromIndex.rawValue
        input.data32 = UInt32(index)
        let output = try call(input)
        try Self.validateFirmwareResult(output.result)
        let name = Self.fourCharacterString(output.key)
        guard name.count == 4, name.unicodeScalars.allSatisfy({ $0.isASCII }) else { continue }
        names.append(name)
      }
      return names
    }
  }

  func writeKey(_ key: String, bytes: [UInt8]) throws {
    try lock.withLock {
      let keyCode = try Self.fourCharacterCode(key)
      var infoInput = AppleSMCParam()
      infoInput.key = keyCode
      infoInput.data8 = AppleSMCCommand.readKeyInfo.rawValue
      let infoOutput = try call(infoInput)
      try Self.validateFirmwareResult(infoOutput.result)

      let size = Int(infoOutput.keyInfo.dataSize)
      guard (1...32).contains(size), bytes.count == size else {
        throw AppleSMCError.invalidPayload
      }

      var writeInput = AppleSMCParam()
      writeInput.key = keyCode
      writeInput.keyInfo.dataSize = infoOutput.keyInfo.dataSize
      writeInput.data8 = AppleSMCCommand.writeBytes.rawValue
      writeInput.bytes = Self.bytesTuple(bytes)
      let output = try call(writeInput)
      try Self.validateFirmwareResult(output.result)
    }
  }

  private func readKeyLocked(_ key: String) throws -> AppleSMCKeyValue {
    let keyCode = try Self.fourCharacterCode(key)
    var infoInput = AppleSMCParam()
    infoInput.key = keyCode
    infoInput.data8 = AppleSMCCommand.readKeyInfo.rawValue
    let infoOutput = try call(infoInput)
    try Self.validateFirmwareResult(infoOutput.result)

    let size = Int(infoOutput.keyInfo.dataSize)
    guard (1...32).contains(size) else { throw AppleSMCError.invalidPayload }

    var readInput = AppleSMCParam()
    readInput.key = keyCode
    readInput.keyInfo.dataSize = infoOutput.keyInfo.dataSize
    readInput.data8 = AppleSMCCommand.readBytes.rawValue
    let readOutput = try call(readInput)
    try Self.validateFirmwareResult(readOutput.result)

    let bytes = withUnsafeBytes(of: readOutput.bytes) { rawBuffer in
      Array(rawBuffer.prefix(size))
    }
    let type = Self.fourCharacterString(infoOutput.keyInfo.dataType)
    return AppleSMCKeyValue(bytes: bytes, dataType: type)
  }

  private func call(_ input: AppleSMCParam) throws -> AppleSMCParam {
    var input = input
    var output = AppleSMCParam()
    var outputSize = MemoryLayout<AppleSMCParam>.stride
    let result = IOConnectCallStructMethod(
      connection,
      UInt32(AppleSMCCommand.kernelIndex.rawValue),
      &input,
      MemoryLayout<AppleSMCParam>.stride,
      &output,
      &outputSize)
    guard result == kIOReturnSuccess else { throw AppleSMCError.ioKit(result) }
    guard outputSize == MemoryLayout<AppleSMCParam>.stride else {
      throw AppleSMCError.invalidPayload
    }
    return output
  }

  private static func validateFirmwareResult(_ value: UInt8) throws {
    guard value == 0 else { throw AppleSMCError.firmware(value) }
  }

  private static func fourCharacterCode(_ key: String) throws -> UInt32 {
    let bytes = Array(key.utf8)
    guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else {
      throw AppleSMCError.invalidKey
    }
    return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
  }

  private static func fourCharacterString(_ code: UInt32) -> String {
    let bytes: [UInt8] = [
      UInt8((code >> 24) & 0xFF),
      UInt8((code >> 16) & 0xFF),
      UInt8((code >> 8) & 0xFF),
      UInt8(code & 0xFF),
    ]
    return String(bytes: bytes, encoding: .ascii) ?? "????"
  }

  private static func bytesTuple(_ values: [UInt8]) -> AppleSMCParam.Bytes32 {
    let bytes = values + Array(repeating: 0, count: 32 - values.count)
    return (
      bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
      bytes[16], bytes[17], bytes[18], bytes[19], bytes[20], bytes[21], bytes[22], bytes[23],
      bytes[24], bytes[25], bytes[26], bytes[27], bytes[28], bytes[29], bytes[30], bytes[31])
  }
}

nonisolated struct AppleSMCParam {
  typealias Bytes32 = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

  struct Version {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
  }

  struct PowerLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpu: UInt32 = 0
    var gpu: UInt32 = 0
    var memory: UInt32 = 0
  }

  struct KeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var attributes: UInt8 = 0
  }

  var key: UInt32 = 0
  var version = Version()
  var powerLimit = PowerLimitData()
  var keyInfo = KeyInfo()
  var padding: UInt16 = 0
  var result: UInt8 = 0
  var status: UInt8 = 0
  var data8: UInt8 = 0
  var data32: UInt32 = 0
  var bytes: Bytes32 = (
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}
