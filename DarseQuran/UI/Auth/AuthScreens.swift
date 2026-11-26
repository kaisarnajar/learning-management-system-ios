import SwiftUI

// MARK: - sign in

struct SignInScreen: View {
    var body: some View {
        WithModel({ app in AuthModel(auth: app.auth, onGoogleSignedIn: { googleWelcomeCheck(app) }) }) { model in
            SignInContent(model: model)
        }
    }
}

private struct SignInContent: View {
    let model: AuthModel
    @Environment(Navigator.self) private var nav
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        let state = model.state
        // The keyboard's Done follows the same rule as the button.
        let canSignIn = email.contains("@") && !password.isEmpty
        AuthFrame(title: "Welcome back", subtitle: signInSubtitle, onBack: { nav.pop() }) {
            if let error = state.error { Banner(error, tone: .danger) }
            if let info = state.info { Banner(info, tone: .success) }
            if let address = state.unverifiedEmail {
                TextButton("Send the verification e-mail again") { model.resend(email: address) }
            }
            EmailField(value: $email)
            PasswordField(value: $password, label: "Password", onDone: { if canSignIn { model.login(email: email, password: password) } })
            HStack { Spacer(); TextButton("Forgot password?") { nav.push(.forgotPassword) } }
            PrimaryButton("Sign in", enabled: canSignIn, loading: state.busy) { model.login(email: email, password: password) }
            GoogleButton(model: model)
            Spacer().frame(height: 8)
            HStack(spacing: 0) {
                Text("New to the academy?").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                TextButton("Create an account") { nav.replace(upTo: .signIn, with: .register) }
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: state.done) { _, done in if done { nav.pop() } }
    }
}

/// "or", then "Continue with Google". [canStart] is asked first; false stops before Google's sheet opens (it reports
/// why itself). Hidden while the Google client IDs aren't set.
private struct GoogleButton: View {
    let model: AuthModel
    var canStart: () -> Bool = { true }

    var body: some View {
        if googleSignInAvailable {
            HStack(spacing: 0) {
                HairlineDivider().frame(maxWidth: .infinity)
                Text("  or  ").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurface)
                HairlineDivider().frame(maxWidth: .infinity)
            }
            SecondaryButton("Continue with Google") {
                guard canStart() else { return }
                Task {
                    switch await requestGoogleIdToken() {
                    case .token(let token): model.google(idToken: token)
                    case .cancelled: break
                    case .failed(let message): model.googleFailed(message)
                    }
                }
            }
        }
    }
}

// MARK: - register

struct RegisterScreen: View {
    var body: some View {
        WithModel({ app in AuthModel(auth: app.auth, onGoogleSignedIn: { googleWelcomeCheck(app) }) }) { model in
            RegisterContent(model: model)
        }
    }
}

private struct RegisterContent: View {
    let model: AuthModel
    @Environment(Navigator.self) private var nav
    @Environment(AppContainer.self) private var app
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var accepted = false

    var body: some View {
        let state = model.state
        Group {
            if state.done && !state.googleSignedIn {
                MessageState(
                    icon: .markEmailRead,
                    title: "Check your e-mail",
                    message: "We sent a verification link to \(email). Open it to activate your account, then sign in.",
                    action: "Continue",
                    onAction: { nav.pop() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Scheme.background.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
            } else {
                form(state)
            }
        }
        // Google accounts are already verified: go straight on, without the "check your e-mail" step.
        .onChange(of: state.googleSignedIn) { _, signedIn in if signedIn { nav.pop() } }
    }

    private func form(_ state: AuthState) -> some View {
        let privacyUrl = app.config?.policies.privacyPolicyUrl ?? "/privacy-policy"
        let termsUrl = app.config?.policies.termsUrl ?? "/terms-and-conditions"
        let canRegister = accepted && email.contains("@") && password.count >= 8 && name.trimmed.count >= 2
        return AuthFrame(title: "Create Account", subtitle: registerSubtitle, onBack: { nav.pop() }) {
            if let error = state.error { Banner(error, tone: .danger) }
            OutlinedField(
                label: "Full name",
                text: Binding(get: { name }, set: { name = String($0.prefix(100)) }),
                contentType: .name,
                capitalization: .words,
                autocorrect: false
            )
            EmailField(value: $email)
            PasswordField(value: $password, label: "Password (at least 8 characters)", newPassword: true, onDone: {})
            PolicyConsentRow(accepted: $accepted, termsUrl: termsUrl, privacyUrl: privacyUrl)
            PrimaryButton("Create account", enabled: canRegister, loading: state.busy) {
                model.register(name: name, email: email, password: password)
            }
            GoogleButton(model: model, canStart: {
                if !accepted { model.policiesNotAccepted() }
                return accepted
            })
        }
    }
}

/// The whole row ticks the box; only the two links open the documents.
private struct PolicyConsentRow: View {
    @Binding var accepted: Bool
    let termsUrl: String
    let privacyUrl: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(accepted ? Scheme.primary : Scheme.onSurfaceVariant, lineWidth: 2)
                    .background(accepted ? Scheme.primary : .clear, in: RoundedRectangle(cornerRadius: 2))
                    .frame(width: 18, height: 18)
                if accepted { Icon.check.image.font(.system(size: 12, weight: .bold)).foregroundStyle(Scheme.onPrimary) }
            }
            .frame(width: 20, height: 20)
            Text(consentText)
                .textStyle(Typo.bodyMedium)
                .foregroundStyle(Scheme.onSurface)
                .tint(Scheme.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.openURL, OpenURLAction { url in
                    switch url.host {
                    case "terms": openWeb(termsUrl)
                    case "privacy": openWeb(privacyUrl)
                    default: break
                    }
                    return .handled
                })
        }
        .contentShape(Rectangle())
        .onTapGesture { accepted.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(accepted ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { accepted.toggle() }
    }

    private var consentText: AttributedString {
        func link(_ text: String, _ host: String) -> AttributedString {
            var part = AttributedString(text)
            part.link = URL(string: "dqa-policy://\(host)")
            part.font = Typo.bodyMedium.with(name: FontName.sansSemiBold).font
            part.foregroundColor = Scheme.primary
            return part
        }
        return AttributedString("I have read and agree to the ") + link("Terms & Conditions", "terms") +
            AttributedString(" and ") + link("Privacy Policy", "privacy") + AttributedString(".")
    }
}

// MARK: - forgot password

struct ForgotPasswordScreen: View {
    var body: some View {
        WithModel({ app in AuthModel(auth: app.auth) }) { model in ForgotPasswordContent(model: model) }
    }
}

private struct ForgotPasswordContent: View {
    let model: AuthModel
    @Environment(Navigator.self) private var nav
    @State private var email = ""

    var body: some View {
        let state = model.state
        DetailScaffold("Reset password") {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if state.done {
                        MessageState(
                            icon: .markEmailRead,
                            title: "Check your e-mail",
                            message: "If an account uses \(email), a reset link is on its way. Open it on this phone to choose a new password.",
                            action: "Back to sign in",
                            onAction: { nav.pop() }
                        )
                    } else {
                        Text("Enter your account's e-mail. We'll send you a link to choose a new password.")
                            .textStyle(Typo.bodyLarge)
                            .foregroundStyle(Scheme.onSurface)
                        if let error = state.error { Banner(error, tone: .danger) }
                        EmailField(value: $email, submitLabel: .done)
                        PrimaryButton("Send reset link", enabled: email.contains("@"), loading: state.busy) { model.forgot(email: email) }
                    }
                }
                .padding(Spacing.screen)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - pieces

/// The green hero with the logo, title and subtitle, then the form (Android's AuthFrame).
private struct AuthFrame<Content: View>: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HeroBox {
                    VStack(alignment: .leading, spacing: 0) {
                        IconButton(.back, label: "Back", tint: Brand.onHero, action: onBack)
                        VStack(spacing: 0) {
                            Image("Logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 72, height: 72)
                                .background(Color.white)
                                .clipShape(Circle())
                                .accessibilityHidden(true)
                            Spacer().frame(height: 14)
                            Text(title)
                                .textStyle(Typo.headlineMedium)
                                .foregroundStyle(Brand.onHero)
                                .multilineTextAlignment(.center)
                                .accessibilityAddTraits(.isHeader)
                            Spacer().frame(height: 6)
                            Text(subtitle)
                                .textStyle(Typo.bodyMedium)
                                .foregroundStyle(Brand.onHero.opacity(0.85))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
                VStack(alignment: .leading, spacing: 14) { content() }
                    .padding(24)
                    .background(Scheme.background)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(alignment: .top) {
            // The hero's green runs up under the status bar, and the page's background below it.
            VStack(spacing: 0) {
                LinearGradient(colors: [Brand.hero, Brand.hero], startPoint: .top, endPoint: .bottom).frame(height: 300)
                Scheme.background
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The e-mail field: trimmed as typed (Android's EmailField).
private struct EmailField: View {
    @Binding var value: String
    var submitLabel: SubmitLabel = .next

    var body: some View {
        OutlinedField(
            label: "E-mail",
            text: Binding(get: { value }, set: { value = $0.trimmed }),
            keyboard: .emailAddress,
            contentType: .username,
            capitalization: .never,
            autocorrect: false,
            submitLabel: submitLabel
        )
    }
}

/// A password field with show / hide, at most 128 characters (Android's PasswordField).
private struct PasswordField: View {
    @Binding var value: String
    let label: String
    var newPassword = false
    let onDone: () -> Void

    var body: some View {
        OutlinedField(
            label: label,
            text: Binding(get: { value }, set: { value = String($0.prefix(128)) }),
            secure: true,
            contentType: newPassword ? .newPassword : .password,
            submitLabel: .done,
            onSubmit: onDone
        )
    }
}
