import Foundation
import XCTest
@testable import DarseQuran

/// A fresh app container whose requests go to [server] and whose session lives in memory (Android's tests use the
/// app's own container against MockWebServer).
@MainActor
func testContainer(_ server: StubServer) -> AppContainer {
    CurrentEnvironment.testBaseUrl = server.baseUrl
    let suite = "tests-\(UUID().uuidString)"
    let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    return AppContainer(secureStore: MemoryStore(), defaults: UserDefaults(suiteName: suite)!, urlSession: server.session, cacheDir: cacheDir)
}


/// Shared mutable state for a stub server's handler (it runs on a background thread).
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    var get: Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
    func update<T>(_ change: (inout Value) -> T) -> T { lock.withLock { change(&value) } }
}

extension StubServer.Request {
    var text: String { String(decoding: body, as: UTF8.self) }
}

let studentTokens = TokenResponse(accessToken: "a", refreshToken: "r", user: SessionUser(id: "u1", email: "student@example.test"))
