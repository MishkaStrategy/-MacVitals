import Dispatch
import Foundation

protocol MemoryPressureProviding: Sendable {
  func currentLevel() -> MemoryPressureLevel
}

nonisolated enum MemoryPressureMapper {
  static func level(normal: Bool, warning: Bool, critical: Bool) -> MemoryPressureLevel {
    if critical { return .critical }
    if warning { return .warning }
    if normal { return .normal }
    return .unknown
  }

  static func level(for event: DispatchSource.MemoryPressureEvent) -> MemoryPressureLevel {
    level(
      normal: event.contains(.normal),
      warning: event.contains(.warning),
      critical: event.contains(.critical))
  }
}

final class MemoryPressureMonitor: MemoryPressureProviding, @unchecked Sendable {
  private let lock = NSLock()
  private let source: any DispatchSourceMemoryPressure
  private var level: MemoryPressureLevel = .unknown

  init(queue: DispatchQueue = DispatchQueue(label: "com.mishkacher.MacVitals.memory-pressure")) {
    source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.normal, .warning, .critical],
      queue: queue)
    source.setEventHandler { [weak self] in
      self?.captureCurrentEvent()
    }
    source.activate()
  }

  deinit {
    source.cancel()
  }

  func currentLevel() -> MemoryPressureLevel {
    lock.lock()
    defer { lock.unlock() }
    return level
  }

  private func captureCurrentEvent() {
    let nextLevel = MemoryPressureMapper.level(for: source.data)
    lock.lock()
    level = nextLevel
    lock.unlock()
  }
}
