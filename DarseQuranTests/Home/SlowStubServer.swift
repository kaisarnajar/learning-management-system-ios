import Foundation
@testable import DarseQuran

/// A [StubServer] whose answers can take their time without holding up the others (MockWebServer's headersDelay).
///
/// StubServer's handler runs on the URL loading thread, so a `Thread.sleep` there delays every request in the test
/// process behind it; here the delay is a timer on that thread's run loop instead.
final class SlowStubServer: @unchecked Sendable {
    typealias Answer = (response: StubServer.Response, delay: TimeInterval)

    var handler: @Sendable (StubServer.Request) -> Answer = { _ in (.json("{}"), 0) }
    private let lock = NSLock()
    private var _requests: [StubServer.Request] = []
    var requests: [StubServer.Request] { lock.withLock { _requests } }

    let id = UUID().uuidString
    var baseUrl: String { "https://slow-\(id.prefix(8).lowercased()).test" }

    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlowStubProtocol.self]
        config.httpAdditionalHeaders = ["X-Slow-Stub": id]
        config.httpMaximumConnectionsPerHost = 16
        return URLSession(configuration: config)
    }()

    init() { SlowStubProtocol.register(self) }
    deinit { SlowStubProtocol.unregister(self) }

    fileprivate func answer(_ request: URLRequest) -> Answer {
        var headers = request.allHTTPHeaderFields ?? [:]
        headers.removeValue(forKey: "X-Slow-Stub")
        let body = request.httpBody ?? request.httpBodyStream.map(readStream) ?? Data()
        let r = StubServer.Request(method: request.httpMethod ?? "GET", url: request.url!, path: request.url!.path, headers: headers, body: body)
        lock.withLock { _requests.append(r) }
        return handler(r)
    }
}

private func readStream(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let n = stream.read(&buffer, maxLength: buffer.count)
        if n <= 0 { break }
        data.append(buffer, count: n)
    }
    return data
}

final class SlowStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var servers: [String: SlowStubServer] = [:]
    private static let lock = NSLock()
    private var timer: Timer?

    static func register(_ server: SlowStubServer) { lock.withLock { servers[server.id] = server } }
    static func unregister(_ server: SlowStubServer) { _ = lock.withLock { servers.removeValue(forKey: server.id) } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Slow-Stub") ?? ""
        guard let server = Self.lock.withLock({ Self.servers[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let (response, delay) = server.answer(request)
        let send: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            let http = HTTPURLResponse(url: self.request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if delay <= 0 { send(); return }
        let timer = Timer(timeInterval: delay, repeats: false) { _ in send() }
        self.timer = timer
        RunLoop.current.add(timer, forMode: .common)
    }

    override func stopLoading() { timer?.invalidate(); timer = nil }
}
