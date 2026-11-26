import Foundation

/// An access token this close to running out is refreshed before a request is sent: sending it would only earn a 401
/// and a second round trip. The margin also covers the time between the server issuing the token and the app saving it.
private let refreshAhead: TimeInterval = 60

/// A file sent in a multipart form.
struct FilePart: Sendable {
    var name: String
    var filename: String
    var mimeType: String
    var data: Data
}

/// What a request sends: nothing, JSON, or a multipart form (text fields and files).
enum RequestBody: Sendable {
    case none
    case json(Data)
    case multipart(fields: [(String, String)], files: [FilePart])
}

/// The one HTTP client for /api/v1 (Android's Network: OkHttp + Retrofit + the token Authenticator).
///
/// It adds the Bearer token only for the academy's own server (images and files can live elsewhere and must not see
/// it), refreshes a token that is about to run out before sending, and on a 401 refreshes the pair once and retries.
/// Refreshes go through [TokenRefresher], which runs one at a time (refresh tokens are single use).
final class APIClient: Sendable {
    let session: URLSession
    private let sessions: SessionSource
    private let refresher: TokenRefresher
    private let clock: @Sendable () -> Date
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(sessions: SessionSource, urlSession: URLSession? = nil, clock: @escaping @Sendable () -> Date = Date.init) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 70 // receipts are rendered on demand
        config.timeoutIntervalForResource = 120
        config.requestCachePolicy = .useProtocolCachePolicy
        let urlSession = urlSession ?? URLSession(configuration: config)
        self.session = urlSession
        self.sessions = sessions
        self.clock = clock
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.refresher = TokenRefresher(sessions: sessions, urlSession: urlSession)
    }

    // MARK: - typed calls

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await decode(send("GET", path, query: query))
    }

    func post<T: Decodable>(_ path: String, _ body: some Encodable, query: [String: String?] = [:]) async throws -> T {
        try await decode(send("POST", path, query: query, body: .json(encoder.encode(body))))
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await decode(send("POST", path))
    }

    func put<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        try await decode(send("PUT", path, body: .json(encoder.encode(body))))
    }

    func patch<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        try await decode(send("PATCH", path, body: .json(encoder.encode(body))))
    }

    func patch<T: Decodable>(_ path: String) async throws -> T {
        try await decode(send("PATCH", path))
    }

    func delete<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await decode(send("DELETE", path, query: query))
    }

    func delete<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        try await decode(send("DELETE", path, body: .json(encoder.encode(body))))
    }

    func multipart<T: Decodable>(_ path: String, method: String = "POST", fields: [(String, String)], files: [FilePart]) async throws -> T {
        try await decode(send(method, path, body: .multipart(fields: fields, files: files)))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - raw

    /// The URL of an API path ("courses/1" → https://host/api/v1/courses/1), or an absolute URL as given.
    /// Throws URLError(.badURL) for a path that can't be made into a URL even percent-encoded (a server-supplied file path
    /// with spaces or Urdu letters is encoded; Android's OkHttp throws inside the call the same way, never crashes).
    func url(_ path: String, query: [String: String?] = [:]) throws -> URL {
        let base: String
        if path.hasPrefix("http://") || path.hasPrefix("https://") { base = path }
        else if path.hasPrefix("/") { base = CurrentEnvironment.baseUrl + path }
        else { base = CurrentEnvironment.baseUrl + "/api/v1/" + path }
        guard var components = URLComponents(string: base)
            ?? base.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URLComponents.init(string:))
        else { throw URLError(.badURL) }
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }.sorted { $0.name < $1.name }
        if !items.isEmpty { components.queryItems = (components.queryItems ?? []) + items }
        // "+" in a query value is a space to most servers: encode it.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    /// Sends a request and returns the body of a 2xx answer; anything else throws [HTTPError].
    func send(_ method: String, _ path: String, query: [String: String?] = [:], body: RequestBody = .none) async throws -> Data {
        let (data, _) = try await sendWithResponse(method, path, query: query, body: body)
        return data
    }

    /// [send], also returning the response (for downloads that need the file name or type).
    func sendWithResponse(_ method: String, _ path: String, query: [String: String?] = [:], body: RequestBody = .none) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: try url(path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch body {
        case .none:
            break
        case .json(let data):
            request.httpBody = data
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        case .multipart(let fields, let files):
            let boundary = "Boundary-\(UUID().uuidString)"
            request.httpBody = Multipart.body(boundary: boundary, fields: fields, files: files)
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request)
    }

    /// GETs [url] as the signed-in user (the token goes to the academy server only), for private pictures such as payment
    /// screenshots, which `/api/files/private/...` refuses without it (Android's Coil uses the same authorized client).
    func authorizedData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try await perform(request).0
    }

    private func perform(_ original: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await authorized(original, load: load, body: { $0 })
    }

    /// Sends [original] with the Bearer token (academy server only), and on a 401 refreshes the pair once and retries.
    /// [load] fetches the answer (into memory, or into a file); [body] reads a failed answer's body for its message.
    private func authorized<Payload>(
        _ original: URLRequest,
        load: (URLRequest) async throws -> (Payload, HTTPURLResponse),
        body: (Payload) -> Data
    ) async throws -> (Payload, HTTPURLResponse) {
        func checked(_ payload: Payload, _ response: HTTPURLResponse) throws -> (Payload, HTTPURLResponse) {
            guard (200..<300).contains(response.statusCode) else { throw HTTPError(status: response.statusCode, body: body(payload)) }
            return (payload, response)
        }
        var request = original
        var sentToken: String? = nil
        if let url = request.url, isAcademyServer(url), let token = await tokenToSend() {
            sentToken = token
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (payload, response) = try await load(request)
        guard response.statusCode == 401, let used = sentToken else { return try checked(payload, response) }
        // A request from before an environment switch: its 401 says nothing about the current session, and retrying
        // would send the new environment's token to the old server.
        guard let url = request.url, isAcademyServer(url) else { return try checked(payload, response) }
        guard let fresh = await refresher.freshToken(used: used) else { return try checked(payload, response) }
        // The refused answer is dropped (for a download, [body] also removes its temporary file).
        _ = body(payload)
        request.setValue("Bearer \(fresh)", forHTTPHeaderField: "Authorization")
        let (retryPayload, retryResponse) = try await load(request)
        return try checked(retryPayload, retryResponse)
    }

    private func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    /// Downloads a GET answer straight to a temporary file (receipts and course attachments can be large; Android
    /// streams them too). The caller moves the file where it belongs.
    func downloadToFile(_ path: String, query: [String: String?] = [:]) async throws -> (URL, HTTPURLResponse) {
        var request = URLRequest(url: try url(path, query: query))
        request.httpMethod = "GET"
        let session = self.session
        return try await authorized(request, load: { request in
            let (temp, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            // The system may remove its temporary file once this returns: keep our own.
            let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: temp, to: kept)
            return (kept, http)
        }, body: { file in
            defer { try? FileManager.default.removeItem(at: file) }
            return (try? Data(contentsOf: file)) ?? Data()
        })
    }


    /// The token for a request now: the current one, or a fresh one when it is about to run out (nil when signed out,
    /// or when the early refresh was rejected and the user is signed out).
    private func tokenToSend() async -> String? {
        // A session belongs to one environment: during a switch the old one must not reach the new server.
        guard let s = sessions.current, s.env == CurrentEnvironment.value else { return nil }
        if let expires = s.expiresAt, clock() >= expires.addingTimeInterval(-refreshAhead) {
            if let fresh = await refresher.freshToken(used: s.accessToken) { return fresh }
            guard let now = sessions.current, now.env == CurrentEnvironment.value else { return nil }
            return now.accessToken
        }
        return s.accessToken
    }

    private func isAcademyServer(_ url: URL) -> Bool {
        guard let base = URL(string: CurrentEnvironment.baseUrl) else { return false }
        return url.scheme == base.scheme && url.host == base.host && effectivePort(url) == effectivePort(base)
    }
}

private func effectivePort(_ url: URL) -> Int? { url.port ?? (url.scheme == "https" ? 443 : url.scheme == "http" ? 80 : nil) }

/// For calls whose answer the app doesn't read.
struct EmptyResponse: Decodable, Sendable {}

/// Runs token refreshes one at a time. Callers that waited while another refreshed get that new token instead of
/// refreshing again (refresh tokens are single use).
actor TokenRefresher {
    private let sessions: SessionSource
    private let urlSession: URLSession
    private var inFlight: Task<String?, Never>?

    init(sessions: SessionSource, urlSession: URLSession) {
        self.sessions = sessions
        self.urlSession = urlSession
    }

    /// The access token to use instead of [used]: refreshes the pair, unless another request already did so. Nil when
    /// there is no session for the current environment or the refresh failed.
    func freshToken(used: String?) async -> String? {
        if let running = inFlight { return await running.value }
        let task = Task { await self.refresh(used: used) }
        inFlight = task
        let token = await task.value
        inFlight = nil
        return token
    }

    private func refresh(used: String?) async -> String? {
        guard let current = sessions.current, current.env == CurrentEnvironment.value else { return nil }
        // Someone else already refreshed while this request waited.
        if current.accessToken != used { return current.accessToken }
        do {
            var request = URLRequest(url: URL(string: CurrentEnvironment.baseUrl + "/api/v1/auth/refresh")!)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(RefreshRequest(refreshToken: current.refreshToken))
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 { sessions.expire(current); return nil }
            guard (200..<300).contains(status) else { return nil }
            let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
            sessions.saveRefreshed(current, tokens)
            // Switched environment while refreshing: don't send to the old server.
            guard current.env == CurrentEnvironment.value else { return nil }
            return tokens.accessToken
        } catch {
            return nil
        }
    }
}

enum Multipart {
    static func body(boundary: String, fields: [(String, String)], files: [FilePart]) -> Data {
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }
        for (name, value) in fields {
            add("--\(boundary)\r\n")
            add("Content-Disposition: form-data; name=\"\(name)\"\r\n")
            add("Content-Type: text/plain; charset=utf-8\r\n\r\n")
            add("\(value)\r\n")
        }
        for file in files {
            add("--\(boundary)\r\n")
            add("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\n")
            add("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            add("\r\n")
        }
        add("--\(boundary)--\r\n")
        return body
    }
}
