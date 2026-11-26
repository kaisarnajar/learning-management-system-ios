import Foundation
@testable import DarseQuran

/// A fake HTTP server for tests (Android's MockWebServer): requests made through [session] are answered by [handler].
final class StubServer: @unchecked Sendable {
    struct Request {
        let method: String
        let url: URL
        let path: String
        let headers: [String: String]
        let body: Data

        var authorization: String? { headers["Authorization"] }
        func json<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(type, from: body) }
    }

    struct Response {
        var status: Int = 200
        var body: Data = Data("{}".utf8)
        var headers: [String: String] = ["Content-Type": "application/json"]

        static func json(_ text: String, status: Int = 200) -> Response { Response(status: status, body: Data(text.utf8)) }
    }

    /// Answers a request. Runs on a background thread.
    var handler: @Sendable (Request) -> Response = { _ in .json("{}") }
    private let lock = NSLock()
    private var _requests: [Request] = []
    var requests: [Request] { lock.withLock { _requests } }

    let id = UUID().uuidString
    /// A base URL unique to this server ("https://stub-<id>.test").
    var baseUrl: String { "https://stub-\(id.prefix(8).lowercased()).test" }

    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Stub-Server": id]
        return URLSession(configuration: config)
    }()

    init() { StubURLProtocol.register(self) }
    deinit { StubURLProtocol.unregister(self) }

    fileprivate func answer(_ request: URLRequest) -> Response {
        let body = request.httpBody ?? request.httpBodyStream.map(readAll) ?? Data()
        var headers = request.allHTTPHeaderFields ?? [:]
        headers.removeValue(forKey: "X-Stub-Server")
        let r = Request(method: request.httpMethod ?? "GET", url: request.url!, path: request.url!.path, headers: headers, body: body)
        lock.withLock { _requests.append(r) }
        return handler(r)
    }
}

private func readAll(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let n = stream.read(buffer, maxLength: 4096)
        if n <= 0 { break }
        data.append(buffer, count: n)
    }
    return data
}

/// Routes requests to the [StubServer] named in their X-Stub-Server header.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var servers: [String: StubServer] = [:]
    private static let lock = NSLock()

    static func register(_ server: StubServer) { lock.withLock { servers[server.id] = server } }
    static func unregister(_ server: StubServer) { _ = lock.withLock { servers.removeValue(forKey: server.id) } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "X-Stub-Server") ?? ""
        guard let server = Self.lock.withLock({ Self.servers[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = server.answer(request)
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
