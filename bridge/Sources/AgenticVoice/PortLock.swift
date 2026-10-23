import Darwin

/// An exclusive bind on a 127.0.0.1 port, used as a cross-process lock. The OS releases it if
/// this process exits. Node's BridgeProcess takes the same port the same way.
final class PortLock {
    /// Coordinates which process starts the bridge, so only one loads the model.
    static let bridgeStartup: UInt16 = 19000

    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    /// Returns nil when another process holds the port.
    static func acquire(_ port: UInt16) -> PortLock? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        // Children (node) must not inherit the lock and keep it alive.
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else {
            close(descriptor)
            return nil
        }
        return PortLock(descriptor: descriptor)
    }

    func release() {
        guard descriptor >= 0 else { return }
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}
