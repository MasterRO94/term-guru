import Foundation

public final class SocketConnection: @unchecked Sendable {
    public let id: Int
    let fd: Int32
    private var buffer = Data()
    private var source: DispatchSourceRead?
    private let queue: DispatchQueue
    public var onLine: ((String) -> Void)?
    public var onClose: (() -> Void)?
    private var closed = false

    init(id: Int, fd: Int32, queue: DispatchQueue) {
        self.id = id; self.fd = fd; self.queue = queue
    }

    func resume() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [fd] in Darwin.close(fd) }
        self.source = source
        source.resume()
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 65536)
        let count = read(fd, &chunk, chunk.count)
        if count <= 0 {
            if count < 0, errno == EAGAIN || errno == EINTR { return }
            close()
            return
        }
        buffer.append(contentsOf: chunk[..<count])
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            onLine?(line)
        }
    }

    public func send(_ line: String) {
        guard !closed else { return }
        var bytes = Array((line + "\n").utf8)
        var offset = 0
        var retries = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeMutableBytes { write(fd, $0.baseAddress! + offset, $0.count - offset) }
            if written > 0 { offset += written; continue }
            // A stalled peer must never block the app; drop the connection instead.
            if errno == EAGAIN, retries < 20 { retries += 1; usleep(1000); continue }
            if errno == EINTR { continue }
            close()
            return
        }
    }

    public func close() {
        guard !closed else { return }
        closed = true
        source?.cancel()
        onClose?()
    }
}

public final class SocketServer {
    private let path: String
    private let queue: DispatchQueue
    private var listener: DispatchSourceRead?
    private var nextID = 1
    private let onConnect: (SocketConnection) -> Void

    public init(path: URL = GuruPaths.socket, queue: DispatchQueue = .main, onConnect: @escaping (SocketConnection) -> Void) {
        self.path = path.path
        self.queue = queue
        self.onConnect = onConnect
    }

    public func start() throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var address = try SocketAddress.make(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 64) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAll(fd) }
        source.setCancelHandler { Darwin.close(fd) }
        listener = source
        source.resume()
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        unlink(path)
    }

    private func acceptAll(_ listenFD: Int32) {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            let connection = SocketConnection(id: nextID, fd: fd, queue: queue)
            nextID += 1
            onConnect(connection)
            connection.resume()
        }
    }
}

enum SocketAddress {
    static func make(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }
}

/// Blocking client used by the CLI and the bash relay.
public final class SocketClient {
    public let fd: Int32

    public init?(path: URL = GuruPaths.socket) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var address = try? SocketAddress.make(path.path) else { return nil }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { Darwin.close(fd); return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        self.fd = fd
    }

    deinit { Darwin.close(fd) }

    @discardableResult
    public func send(_ line: String) -> Bool {
        let bytes = Array((line + "\n").utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { write(fd, $0.baseAddress! + offset, $0.count - offset) }
            if written <= 0 { if errno == EINTR { continue }; return false }
            offset += written
        }
        return true
    }

    public func readLine(timeout: TimeInterval) -> String? {
        var line = [UInt8]()
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remaining = Int32(max(0, deadline.timeIntervalSinceNow * 1000))
            guard poll(&descriptor, 1, remaining) > 0 else { return nil }
            var byte: UInt8 = 0
            guard read(fd, &byte, 1) == 1 else { return nil }
            if byte == 0x0A { return String(decoding: line, as: UTF8.self) }
            line.append(byte)
        }
    }
}
