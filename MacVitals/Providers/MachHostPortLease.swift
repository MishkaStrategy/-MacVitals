import Darwin.Mach

final class MachHostPortLease: @unchecked Sendable {
  static let shared = MachHostPortLease()

  let name: host_t
  private let release: @Sendable (host_t) -> Void

  init(
    acquire: @Sendable () -> host_t = { mach_host_self() },
    release: @escaping @Sendable (host_t) -> Void = { name in
      _ = mach_port_deallocate(mach_task_self_, name)
    }
  ) {
    name = acquire()
    self.release = release
  }

  deinit {
    guard name != MACH_PORT_NULL else { return }
    release(name)
  }
}
