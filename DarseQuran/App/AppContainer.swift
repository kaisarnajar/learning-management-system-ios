import Foundation
import Observation
import SwiftUI

/// The app's dependencies and shared state, one per process (Android's AppContainer). Screens reach it through
/// `@Environment(AppContainer.self)`.
@MainActor
@Observable
final class AppContainer {
    let environments: EnvironmentStore
    @ObservationIgnored let sessionStore: SessionStore
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let client: APIClient
    @ObservationIgnored let api: AcademyAPI
    @ObservationIgnored let auth: AuthRepository
    @ObservationIgnored let repo: AcademyRepository
    let cart: CartStore
    let toaster = Toaster()

    /// The signed-in session for the current server (mirrors [sessionStore] on the main actor).
    private(set) var session: Session?
    /// The server the UI shows; changes only once requests go to the new server and its session is loaded.
    private(set) var environment: AppEnvironment
    var appearance: AppearanceSetting {
        didSet { settings.appearance = appearance }
    }
    /// Branding, lookups (e.g. fatwa categories) and policy links, once loaded.
    private(set) var config: AppConfig?
    /// Set after a Google sign-in, so the profile form follows (the website's /auth/continue).
    var googleWelcomePending = false

    @ObservationIgnored private var lastUserCheck: Date?

    init(
        secureStore: SecureStore = KeychainStore(),
        defaults: UserDefaults = .standard,
        urlSession: URLSession? = nil,
        cacheDir: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    ) {
        let environments = EnvironmentStore(defaults: defaults)
        let env = environments.initial
        let sessionStore = SessionStore(store: secureStore, initialEnvironment: env)
        let client = APIClient(sessions: sessionStore, urlSession: urlSession)
        let api = AcademyAPI(client: client)
        let repo = AcademyRepository(api: api) { env in
            SavedHome(file: cacheDir.appendingPathComponent("home-\(env.key).json"))
        }
        self.environments = environments
        self.sessionStore = sessionStore
        self.settings = SettingsStore(defaults: defaults)
        self.client = client
        self.api = api
        self.auth = AuthRepository(api: api, sessionStore: sessionStore)
        self.repo = repo
        self.cart = CartStore(repo: repo)
        self.session = sessionStore.current
        self.environment = env
        self.appearance = SettingsStore(defaults: defaults).appearance

        sessionStore.observe { [weak self] value in
            Task { @MainActor in self?.sessionChanged(value) }
        }
        Task { await ImageLoader.shared.useAuthorizedFetch { [client] url in try await client.authorizedData(url) } }
        cartOwnerChanged()
        #if DEBUG
        signInFromLaunchEnvironment()
        #endif
    }

    #if DEBUG
    /// Debug builds only: `SIMCTL_CHILD_DQA_EMAIL` / `SIMCTL_CHILD_DQA_PASSWORD` (or DQA_SIGN_OUT=1) given to
    /// `xcrun simctl launch` sign in (or out) on start, so signed-in screens can be checked without typing. The values
    /// come from the launch command, never from the app's files.
    private func signInFromLaunchEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if env["DQA_SIGN_OUT"] == "1" { sessionStore.clear(); session = nil; return }
        guard let email = env["DQA_EMAIL"], let password = env["DQA_PASSWORD"], session?.user.email != email else { return }
        Task { _ = await auth.login(email: email, password: password) }
    }
    #endif

    private func sessionChanged(_ value: Session?) {
        let previous = session?.user.id
        session = value
        if value?.user.id != previous {
            // A different user (sign-out, another account, another environment) must not find the last one's documents.
            DocumentCache.clear()
            ImageLoader.shared.forgetMemory()
            cartOwnerChanged()
        }
    }

    /// The cart belongs to the signed-in student on the current server: fetch it when they sign in, empty it when they
    /// leave, whichever screen is open.
    private func cartOwnerChanged() {
        if let s = session, s.env == environment {
            Task { await cart.refresh() }
        } else {
            cart.clearLocal()
        }
    }

    /// Keeps trying to load the app config until it loads (e.g. after starting offline), backing off to a minute.
    func loadConfig() async {
        var wait: Double = 5
        while config == nil, !Task.isCancelled {
            if let c = await repo.appConfig().value { config = c; return }
            try? await Task.sleep(for: .seconds(wait))
            wait = min(wait * 2, 60)
        }
    }

    /// Re-reads the signed-in user (role, name) when the app comes to the front, at most every 10 minutes: a role
    /// changed on the website then reaches the app without a sign-out.
    func refreshUserIfStale(now: Date = Date()) {
        // The store, not [session]: the main-actor copy catches up a moment after a sign-in.
        guard sessionStore.current != nil else { return }
        if let last = lastUserCheck, now.timeIntervalSince(last) < 10 * 60 { return }
        lastUserCheck = now
        Task { _ = await auth.profile() }
    }

    /// Points the app at another copy of the website (debug build only); that environment's own session becomes current.
    func switchEnvironment(_ env: AppEnvironment) {
        // Session first: until requests point at the new server, its token isn't attached to the old one.
        sessionStore.useEnvironment(env)
        environments.select(env)
        repo.clearCaches()
        config = nil
        environment = env
        let previous = session?.user.id
        session = sessionStore.current
        // sessionChanged will find [session] already updated, so the documents are cleared here.
        if session?.user.id != previous { DocumentCache.clear() }
        cart.clearLocal()
        cartOwnerChanged()
        Task { await loadConfig() }
    }

    /// Runs [block] when signed in; otherwise returns false so the caller opens sign-in.
    var isSignedIn: Bool { session != nil }
}
