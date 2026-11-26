import Foundation
import GoogleSignIn
import UIKit

/// The Google client IDs from Info.plist (Config/Local.xcconfig); blank or unexpanded when not set up.
private func infoValue(_ key: String) -> String? {
    guard let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmed, !value.isEmpty, !value.contains("$(") else { return nil }
    return value
}

/// Google sign-in needs both the iOS client ID and the Web (server) client ID the website checks the token against;
/// without them the button is hidden, as Android hides it without GOOGLE_WEB_CLIENT_ID.
var googleSignInAvailable: Bool { infoValue("GIDClientID") != nil && infoValue("GIDServerClientID") != nil }

/// How a Google sign-in attempt ended.
enum GoogleIdTokenResult {
    case token(String)
    /// The user closed Google's sheet: nothing to say.
    case cancelled
    case failed(String)
}

/// Google sign-in (Android uses Credential Manager): returns the ID token for POST auth/google, or why there is none.
@MainActor
func requestGoogleIdToken() async -> GoogleIdTokenResult {
    let failed = GoogleIdTokenResult.failed("Google sign-in didn't work on this phone. Use your e-mail instead.")
    guard let clientID = infoValue("GIDClientID"), let serverClientID = infoValue("GIDServerClientID"), let presenter = Presenter.top else {
        return failed
    }
    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: serverClientID)
    do {
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let token = result.user.idToken?.tokenString else { return failed }
        return .token(token)
    } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue {
        return .cancelled
    } catch {
        return failed
    }
}

/// Shows the website's welcome after a Google sign-in that goes on to the profile form (Android's GoogleWelcomeEffect
/// dialog). The navigation itself is AppRoot's (container.googleWelcomePending).
@MainActor
func presentGoogleWelcome() {
    let alert = UIAlertController(title: googleWelcomeTitle, message: googleWelcomeBody, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    alert.view.tintColor = UIColor(Scheme.primary)
    Presenter.present(alert)
}

/// After a Google sign-in: a student whose profile is incomplete goes on to the profile form, with the welcome.
@MainActor
func googleWelcomeCheck(_ container: AppContainer) {
    Task { @MainActor in
        let auth = container.auth
        guard await GoogleWelcome.consume({ await auth.profile() }) else { return }
        container.googleWelcomePending = true
        // Let the profile form slide in first; the alert then shows over it.
        try? await Task.sleep(for: .milliseconds(700))
        presentGoogleWelcome()
    }
}
