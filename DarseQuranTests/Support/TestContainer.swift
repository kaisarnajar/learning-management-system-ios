import Foundation
@testable import DarseQuran

/// An AppContainer for tests (Android's tests use the application's container): sessions in memory, settings in a
/// throwaway UserDefaults suite, requests answered by [server], files in a temporary folder. It starts on the default
/// environment; callers restore `CurrentEnvironment.value` afterwards if they switch.
@MainActor
func makeTestContainer(server: StubServer, keychain: SecureStore = MemoryStore()) -> AppContainer {
    let suite = "tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
    try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    return AppContainer(secureStore: keychain, defaults: defaults, urlSession: server.session, cacheDir: cache)
}
