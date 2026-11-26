import Foundation
import Observation
import os

/// [googleSignedIn]: done by Google sign-in, which needs no e-mail verification (unlike [AuthModel.register]).
struct AuthState: Equatable {
    var busy = false
    var error: String? = nil
    var unverifiedEmail: String? = nil
    var info: String? = nil
    var done = false
    var googleSignedIn = false
}

/// Sign-in, registration, password reset and the verification e-mail (Android's AuthViewModel).
@MainActor
@Observable
final class AuthModel {
    private(set) var state = AuthState()
    @ObservationIgnored private let auth: AuthRepository
    /// Runs after a Google sign-in went through (the welcome check; see [GoogleWelcome]).
    @ObservationIgnored private let onGoogleSignedIn: (@MainActor () -> Void)?

    init(auth: AuthRepository, onGoogleSignedIn: (@MainActor () -> Void)? = nil) {
        self.auth = auth
        self.onGoogleSignedIn = onGoogleSignedIn
    }

    /// One request at a time: a second tap while one is on its way (even in the same frame) is ignored.
    private func run<T>(_ block: @escaping () async -> ApiResult<T>, onOk: (() -> Void)? = nil) {
        if state.busy { return }
        state.busy = true
        state.error = nil
        state.info = nil
        Task {
            switch await block() {
            case .success:
                if let onOk { onOk() } else { state = AuthState(done: true) }
            case .failure(let e):
                state.busy = false
                state.error = e.message
                state.unverifiedEmail = nil
            }
        }
    }

    func login(email: String, password: String) {
        if state.busy { return }
        state = AuthState(busy: true)
        let auth = self.auth
        Task {
            switch await auth.login(email: email, password: password) {
            case .success:
                state = AuthState(done: true)
            case .failure(let e):
                state = AuthState(error: e.message, unverifiedEmail: e.code == "email_not_verified" ? email.trimmed : nil)
            }
        }
    }

    func register(name: String, email: String, password: String) {
        let auth = self.auth
        run({ await auth.register(name: name, email: email, password: password) })
    }

    /// Arms [GoogleWelcome] first: saving the session replaces the app's navigation, this screen included.
    func google(idToken: String) {
        if state.busy { return }
        GoogleWelcome.arm()
        let auth = self.auth
        run({
            let result = await auth.google(idToken: idToken)
            if case .failure = result { GoogleWelcome.disarm() }
            return result
        }, onOk: { [weak self] in
            self?.state = AuthState(done: true, googleSignedIn: true)
            self?.onGoogleSignedIn?()
        })
    }

    func googleFailed(_ message: String) { state = AuthState(error: message) }

    /// The website's register page refuses Google sign-in until the policies are accepted.
    func policiesNotAccepted() { state = AuthState(error: policiesRequired) }

    func resend(email: String) {
        let auth = self.auth
        run({ await auth.resendVerification(email: email) }, onOk: { [weak self] in
            self?.state = AuthState(info: "If that account still needs verifying, a new link is on its way to \(email).")
        })
    }

    func forgot(email: String) {
        let auth = self.auth
        run({ await auth.forgotPassword(email: email) })
    }
}

// MARK: - website wording

/// The website's sign-in subtitle (components/auth/LoginForm.tsx).
let signInSubtitle = "Students and instructors use the same sign-in. After the academy links your " +
    "registered email as a teacher, you will open the teacher portal when you sign in."

/// The website's register subtitle (components/auth/RegisterForm.tsx).
let registerSubtitle = "Register to enroll in courses. If the academy adds you as a teacher later, " +
    "sign in with this same email to access the teacher portal."

/// The website's error for Google sign-up before the policies are accepted.
let policiesRequired = "Please agree to the Terms & Conditions and Privacy Policy to continue."

/// The website's banner on /profile?source=google (app/profile/page.tsx).
let googleWelcomeTitle = "Welcome! You signed in with Google."
let googleWelcomeBody = "Your email is verified automatically. Please fill in the required profile " +
    "details below — the academy needs them before you can enroll in any course."

// MARK: - google welcome

/// The website's /auth/continue step: a student who signs in with Google and whose profile is incomplete is sent to
/// the profile form with a welcome message. Signing in replaces the app's navigation (it is keyed by the user), so the
/// sign-in screen arms this before signing in, and the check runs once the sign-in has gone through.
enum GoogleWelcome {
    private static let pending = OSAllocatedUnfairLock(initialState: false)

    static func arm() { pending.withLock { $0 = true } }

    static func disarm() { pending.withLock { $0 = false } }

    /// True, once per Google sign-in, when [profile] says a student still has to complete their profile.
    static func consume(_ profile: @Sendable () async -> ApiResult<Profile>) async -> Bool {
        let armed = pending.withLock { value in
            let was = value
            value = false
            return was
        }
        guard armed else { return false }
        return needsProfileAfterGoogle(await profile())
    }
}

/// As /auth/continue: only students (role USER) are held to a complete profile; an unknown profile sends no one.
func needsProfileAfterGoogle(_ profile: ApiResult<Profile>) -> Bool {
    guard case .success(let p) = profile else { return false }
    return p.role == "USER" && !p.profileComplete
}
