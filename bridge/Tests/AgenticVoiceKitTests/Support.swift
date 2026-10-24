import Darwin
import Foundation
import Network

/// A loopback HTTP server answering each request with `respond(path)`.
final class TestHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    let port: UInt16
    var url: String { "http://127.0.0.1:\(port)" }

    init(port: UInt16 = 0, respond: @escaping @Sendable (String) -> (status: Int, body: String)) async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            Self.receive(connection, Data(), respond)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready: resumed = true; continuation.resume()
                case .failed(let error): resumed = true; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .global())
        }
        self.listener = listener
        self.port = listener.port!.rawValue
    }

    private static func receive(_ connection: NWConnection, _ buffer: Data, _ respond: @escaping @Sendable (String) -> (status: Int, body: String)) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if complete || error != nil { connection.cancel() } else { receive(connection, buffer, respond) }
                return
            }
            let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
            let length = head.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            guard buffer.count - headerEnd.upperBound >= length else {
                receive(connection, buffer, respond)
                return
            }
            let path = head.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let (status, body) = respond(path)
            let response = "HTTP/1.1 \(status) Status\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    func close() {
        listener.cancel()
    }
}

/// A port nothing listens on right now.
func freePort() -> UInt16 {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    defer { Darwin.close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            _ = bind(descriptor, $0, length)
            _ = getsockname(descriptor, $0, &length)
        }
    }
    return UInt16(bigEndian: address.sin_port)
}

/// A temporary directory removed when the test ends.
final class TemporaryDirectory: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("agentic-voice-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func path(_ relative: String) -> String {
        url.appendingPathComponent(relative).path
    }

    /// Writes a file, creating its directory; `mode` makes it executable for scripts.
    @discardableResult
    func write(_ relative: String, _ content: String, mode: Int = 0o644) throws -> String {
        let file = path(relative)
        try FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try content.write(toFile: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file)
        return file
    }

    func read(_ relative: String) throws -> String {
        try String(contentsOfFile: path(relative), encoding: .utf8)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: path(relative))
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Polls until the condition holds, failing after about two seconds.
func eventually(_ condition: () throws -> Bool) async throws {
    for _ in 0..<200 {
        if try condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    struct Timeout: Error {}
    throw Timeout()
}

func alive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0
}
