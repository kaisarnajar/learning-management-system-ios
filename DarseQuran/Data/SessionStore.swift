import Foundation
import os

/// A signed-in session: the token pair, the user it belongs to, and the environment (server) that issued it.
/// [expiresAt] is when the access token runs out, or nil for a session stored before the app kept it.
struct Session: Codable, Sendable, Hashable {
    var accessToken: String
    var refreshToken: String
    var user: SessionUser
    var env: AppEnvironment
    var expiresAt: Date? = nil
}

extension AppEnvironment: Codable {}

extension TokenResponse {
    /// When an access token issued [now] runs out.
    func expiresAt(_ now: Date) -> Date { now.addingTimeInterval(TimeInterval(expiresIn)) }
}

/// What the network layer needs from the session: read it, and record the outcome of a token refresh.
protocol SessionSource: Sendable {
    var current: Session? { get }
    /// Stores the token pair that replaced [old]'s, under [old]'s environment (the app may have switched since).
    func saveRefreshed(_ old: Session, _ tokens: TokenResponse)
    /// [old]'s refresh token was rejected: sign out of [old]'s environment, unless a newer session replaced it.
    func expire(_ old: Session)
}

/// Persists the session in the Keychain. [current] is the single source of truth for "am I signed in?".
///
/// Each environment (production, staging) keeps its own session, so switching servers in the debug build keeps you
/// signed in on each. Held in memory first and persisted second, so a token saved by a refresh is visible to the very
/// next request. Observers (the app's UI state) hear of every change on the main actor.
final class SessionStore: SessionSource, @unchecked Sendable {
    private let store: SecureStore
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var env: AppEnvironment
    private var session: Session?
    private var observers: [@Sendable (Session?) -> Void] = []

    init(store: SecureStore = KeychainStore(), initialEnvironment: AppEnvironment, clock: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.clock = clock
        self.env = initialEnvironment
        self.session = SessionStore.read(store, initialEnvironment)
    }

    var current: Session? { lock.withLock { session } }
    var environment: AppEnvironment { lock.withLock { env } }

    /// [observer] is called (on whatever thread made the change) with every new session value.
    func observe(_ observer: @escaping @Sendable (Session?) -> Void) {
        lock.withLock { observers.append(observer) }
    }

    private func publish(_ value: Session?) {
        let all = lock.withLock { observers }
        all.forEach { $0(value) }
    }

    private static func read(_ store: SecureStore, _ env: AppEnvironment) -> Session? {
        guard let data = store.read(env.key) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    /// Loads the session of [environment]; called before requests are pointed at it.
    func useEnvironment(_ environment: AppEnvironment) {
        let loaded = SessionStore.read(store, environment)
        lock.withLock { env = environment; session = loaded }
        publish(loaded)
    }

    /// Signs in on the current environment.
    func save(_ tokens: TokenResponse, user: SessionUser? = nil) {
        let (env, previous) = lock.withLock { (self.env, session) }
        guard let finalUser = user ?? tokens.user ?? previous?.user else { return }
        write(Session(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, user: finalUser, env: env, expiresAt: tokens.expiresAt(clock())))
    }

    func saveRefreshed(_ old: Session, _ tokens: TokenResponse) {
        // Signed out, or signed in again, while the refresh was in flight: that newer state wins.
        guard stored(old.env)?.refreshToken == old.refreshToken else { return }
        let user = tokens.user ?? old.user
        write(Session(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, user: user, env: old.env, expiresAt: tokens.expiresAt(clock())))
    }

    private func stored(_ env: AppEnvironment) -> Session? {
        let (currentEnv, current) = lock.withLock { (self.env, session) }
        return env == currentEnv ? current : SessionStore.read(store, env)
    }

    private func write(_ value: Session) {
        let isCurrent = lock.withLock { () -> Bool in
            guard value.env == env else { return false }
            session = value
            return true
        }
        if let data = try? JSONEncoder().encode(value) { store.write(data, account: value.env.key) }
        if isCurrent { publish(value) }
    }

    /// Updates the signed-in user's details. Ignored when [user] is someone else: a profile answer that arrives after a
    /// sign-out and another sign-in belongs to the previous account.
    func updateUser(_ user: SessionUser) {
        guard var current = current, current.user.id == user.id else { return }
        current.user = user
        write(current)
    }

    /// Signs out of the current environment.
    func clear() { remove(environment) }

    func expire(_ old: Session) {
        let s = stored(old.env)
        if s == nil || s?.refreshToken == old.refreshToken { remove(old.env) }
    }

    private func remove(_ env: AppEnvironment) {
        let isCurrent = lock.withLock { () -> Bool in
            guard env == self.env else { return false }
            session = nil
            return true
        }
        store.delete(env.key)
        if isCurrent { publish(nil) }
    }
}

/// Light / dark / system, kept in UserDefaults (Android keeps it in the session DataStore).
final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var appearance: AppearanceSetting {
        get { AppearanceSetting(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "theme") }
    }
}
