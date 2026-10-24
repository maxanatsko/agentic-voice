import Darwin
import Synchronization

/// An exclusive bind on a 127.0.0.1 port, used as a cross-process lock. The OS releases it if
/// the holder exits, so a crashed holder never leaves a stale lock.
public final class PortLock: Sendable {
    /// Coordinates which process starts the bridge, so only one loads the model.
    public static let bridgeStartup: UInt16 = 19000
    /// Held by whichever agentic-voice process is speaking, so sessions never talk over each other.
    public static let speaking: UInt16 = 19001

    private let descriptor: Mutex<Int32>

    private init(descriptor: Int32) {
        self.descriptor = Mutex(descriptor)
    }

    /// Returns nil when another process holds the port; throws for any other failure.
    public static func acquire(_ port: UInt16) throws -> PortLock? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw AgenticVoiceError("Cannot create a socket for 127.0.0.1:\(port): \(String(cString: strerror(errno)))") }
        // Child processes must not inherit the lock and keep it alive.
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
            let code = errno
            close(descriptor)
            if code == EADDRINUSE { return nil }
            throw AgenticVoiceError("Cannot bind 127.0.0.1:\(port): \(String(cString: strerror(code)))")
        }
        return PortLock(descriptor: descriptor)
    }

    public func release() {
        descriptor.withLock { descriptor in
            guard descriptor >= 0 else { return }
            close(descriptor)
            descriptor = -1
        }
    }

    deinit {
        release()
    }
}
