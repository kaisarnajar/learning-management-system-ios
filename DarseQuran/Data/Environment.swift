import Foundation
import os

/// A copy of the website. The release build only ever talks to production. The debug build (the developer's own,
/// never shared) starts on staging and can switch between the two in Account → Server.
enum AppEnvironment: String, CaseIterable, Sendable, Hashable {
    case production
    case staging

    var key: String { rawValue }

    var label: String {
        switch self {
        case .production: "Production"
        case .staging: "Staging"
        }
    }

    var baseUrl: String {
        switch self {
        case .production: "https://darsequranacademy.com"
        // Empty in the release build, which has no way to reach it anyway (see [available]).
        case .staging: AppEnvironment.stagingBaseUrl
        }
    }

    var host: String {
        let afterScheme = baseUrl.components(separatedBy: "://").last ?? baseUrl
        return afterScheme.hasSuffix("/") ? String(afterScheme.dropLast()) : afterScheme
    }

    /// From the build settings (Config/*.xcconfig); empty in Release, so the staging URL isn't in the binary.
    static let stagingBaseUrl: String = {
        #if DEBUG
        (Bundle.main.object(forInfoDictionaryKey: "StagingBaseURL") as? String) ?? ""
        #else
        ""
        #endif
    }()

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// The servers this build may talk to.
    static let available: [AppEnvironment] = availableFor(debugBuild: isDebugBuild)

    /// Where this build starts: staging in debug, so testing never touches real data by default.
    static var defaultEnvironment: AppEnvironment { available.last ?? .production }

    static func availableFor(debugBuild: Bool) -> [AppEnvironment] {
        debugBuild ? [.production, .staging] : [.production]
    }

    /// The remembered server, if this build may use it; anything else (an old key, staging in release) is nil.
    static func fromKey(_ key: String?) -> AppEnvironment? { available.first { $0.key == key } }
}

/// The environment requests go to right now. Read on every request and when building image and file URLs, so it is
/// a plain locked value rather than something observed.
enum CurrentEnvironment {
    private static let state = OSAllocatedUnfairLock<(AppEnvironment, String?)>(initialState: (AppEnvironment.defaultEnvironment, nil))

    static var value: AppEnvironment {
        get { state.withLock { $0.0 } }
        set { state.withLock { $0.0 = newValue } }
    }

    /// Tests point requests at a stubbed server; always nil in the app.
    static var testBaseUrl: String? {
        get { state.withLock { $0.1 } }
        set { state.withLock { $0.1 = newValue } }
    }

    static var baseUrl: String {
        let url = testBaseUrl ?? value.baseUrl
        return url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    static var host: String { baseUrl.components(separatedBy: "://").last ?? baseUrl }
}

/// Remembers the server chosen in the debug build. The release build always comes back as production.
final class EnvironmentStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "environment"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        CurrentEnvironment.value = initial
    }

    var initial: AppEnvironment { AppEnvironment.fromKey(defaults.string(forKey: key)) ?? AppEnvironment.defaultEnvironment }

    /// Points requests at [env] and remembers it.
    func select(_ env: AppEnvironment) {
        precondition(AppEnvironment.available.contains(env), "\(env.label) is not available in this build")
        CurrentEnvironment.value = env
        defaults.set(env.key, forKey: key)
    }
}

/// Absolute URL for an image or file path the API returns ("/uploads/x.png" or "https://...").
func resolveUrl(_ path: String?) -> URL? {
    guard let path, !path.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    let full: String
    if path.hasPrefix("http://") || path.hasPrefix("https://") { full = path }
    else if path.hasPrefix("/") { full = CurrentEnvironment.baseUrl + path }
    else { full = CurrentEnvironment.baseUrl + "/" + path }
    return URL(string: full) ?? URL(string: full.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
}
