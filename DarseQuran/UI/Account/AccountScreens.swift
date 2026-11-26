import Observation
import SwiftUI

// Android's AccountScreens.kt: the Account tab and the screens it opens (except Contact, Reviews, Waivers and Server,
// which have their own files).

// MARK: - account

/// The Account tab's state (Android's AccountViewModel): the full profile of whoever is signed in, and the resend.
@MainActor
@Observable
final class AccountModel {
    private(set) var profile: Profile?
    var resend = ResendState()
    @ObservationIgnored private let app: AppContainer

    init(app: AppContainer) { self.app = app }

    func refresh() {
        guard app.session != nil else { profile = nil; return }
        Task { profile = await app.auth.profile().value ?? profile }
    }

    func resendVerification() {
        guard let email = profile?.email ?? app.session?.user.email else { return }
        resend = ResendState(sending: true)
        Task { resend = resendOutcome(await app.auth.resendVerification(email: email)) }
    }

    func signOut() { Task { await app.auth.logout() } }
}

struct AccountScreen: View {
    var body: some View { WithModel({ AccountModel(app: $0) }) { AccountContent(model: $0) } }
}

private struct AccountContent: View {
    let model: AccountModel
    @Environment(AppContainer.self) private var container
    @Environment(Navigator.self) private var nav
    @State private var themeDialog = false
    @State private var confirmSignOut = false

    var body: some View {
        let session = container.session
        let profile = model.profile
        GeometryReader { geo in
        ScrollView {
            VStack(spacing: 0) {
                hero(session: session, profile: profile, statusBar: geo.safeAreaInsets.top)
                // As on the website's profile pages, an unverified e-mail is flagged with a way to resend the link.
                if session != nil, let profile, profile.emailVerified == nil {
                    VerificationBanner(state: model.resend) { model.resendVerification() }
                        .padding(.horizontal, Spacing.screen).padding(.top, 16)
                }
                // Everyone signed in has the same profile pages, as on the website (admins and teachers included).
                if session != nil {
                    AccountGroup(title: "My learning")
                    AccountEntry(icon: .bellFilled, label: "Notifications") { nav.push(.notifications) }
                    AccountEntry(icon: .paymentsFilled, label: "Payments") { nav.push(.payments) }
                    AccountEntry(icon: .requestQuote, label: "Fee waiver requests") { nav.push(.waivers) }
                    AccountEntry(icon: .star, label: "My reviews") { nav.push(.reviews) }
                    AccountEntry(icon: .bagFilled, label: "Book orders") { nav.push(.orders) }
                }
                AccountGroup(title: "Settings")
                if session != nil {
                    AccountEntry(icon: .edit, label: "Edit profile") { nav.push(.editProfile) }
                    if profile?.hasPassword != false {
                        AccountEntry(icon: .key, label: "Change password") { nav.push(.changePassword) }
                    }
                }
                AccountEntry(icon: .contrast, label: "Appearance", trailing: appearanceLabel(container.appearance)) {
                    setWithoutAnimation($themeDialog, true)
                }
                // Only the debug build can switch servers; the release build has just production.
                if AppEnvironment.isDebugBuild {
                    AccountEntry(icon: .server, label: "Server", trailing: container.environment.label) { nav.push(.server) }
                }
                AccountGroup(title: "Academy")
                AccountEntry(icon: .supportAgent, label: "Contact us") { nav.push(.contact) }
                AccountEntry(icon: .infoFilled, label: "About the academy") { nav.push(.about) }
                AccountEntry(icon: .policyFilled, label: "Privacy policy") {
                    openWeb(container.config?.policies.privacyPolicyUrl.nilIfBlank ?? "/privacy-policy")
                }
                AccountEntry(icon: .gavel, label: "Terms & conditions") {
                    openWeb(container.config?.policies.termsUrl.nilIfBlank ?? "/terms-and-conditions")
                }
                if let session {
                    AccountGroup(title: "")
                    AccountEntry(icon: .logout, label: "Sign out") { confirmSignOut = true }
                    if !Roles.isAdmin(session.user.role) {
                        AccountEntry(icon: .deleteForever, label: "Delete my account", danger: true) { nav.push(.deleteAccount) }
                    }
                }
                Text("Version \(appVersion)")
                    .textStyle(Typo.labelSmall)
                    .foregroundStyle(Scheme.onSurfaceVariant)
                    .padding(Spacing.screen)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 32)
        }
        // The hero runs up under the status bar, as on Android.
        .ignoresSafeArea(.container, edges: .top)
        }
        .background(Scheme.background)
        .task(id: session?.user.id) { model.refresh() }
        .reloadOnReturn { model.refresh() }
        .materialDialog("Appearance", isPresented: $themeDialog) {
            VStack(spacing: 0) {
                ForEach([AppearanceSetting.system, .light, .dark], id: \.self) { value in
                    RadioRow(label: appearanceChoice(value), selected: container.appearance == value) {
                        container.appearance = value
                        dismissWithoutAnimation($themeDialog)
                    }
                }
            }
        } buttons: {
            TextButton("Close") { dismissWithoutAnimation($themeDialog) }
        }
        .confirmDialog("Sign out?", message: "You can sign in again at any time.", isPresented: $confirmSignOut, confirm: "Sign out") {
            model.signOut()
        }
    }

    @ViewBuilder
    private func hero(session: Session?, profile: Profile?, statusBar: CGFloat) -> some View {
        HeroBox {
            VStack(alignment: .leading, spacing: 0) {
                if let session {
                    let user = session.user
                    HStack(spacing: 16) {
                        Avatar(name: profile?.name ?? user.name, image: profile?.image ?? user.image, size: 64)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(profile?.name ?? user.name ?? "Student")
                                .textStyle(Typo.headlineSmall).foregroundStyle(Brand.onHero).lineLimit(1).truncationMode(.tail)
                            Text(user.email).textStyle(Typo.bodySmall).foregroundStyle(Brand.onHero.opacity(0.8))
                            if let role = roleLabel(user.role) {
                                Text(role).textStyle(Typo.labelLarge).foregroundStyle(Brand.goldSoft).padding(.top, 6)
                            }
                            if let number = profile?.registrationNumber ?? user.registrationNumber {
                                Text(number).textStyle(Typo.labelLarge).foregroundStyle(Brand.goldSoft).padding(.top, 6)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if profile?.profileComplete == false {
                        Button { nav.push(.editProfile) } label: {
                            Banner("Complete your profile to enrol in courses.", tone: .warning)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 14)
                    }
                } else {
                    Image("Logo").resizable().scaledToFit()
                        .frame(width: 64, height: 64).background(Color.white).clipShape(Circle())
                        .accessibilityHidden(true)
                    Text("Your academy account").textStyle(Typo.headlineSmall).foregroundStyle(Brand.onHero).padding(.top, 14)
                    Text("Sign in to apply for courses, pay fees and follow your progress.")
                        .textStyle(Typo.bodyMedium).foregroundStyle(Brand.onHero.opacity(0.85))
                    HStack(spacing: 10) {
                        PillButton(text: "Sign in", background: Brand.goldSoft, foreground: .black) { nav.push(.signIn) }
                        PillButton(text: "Create account", foreground: Brand.onHero, outline: Scheme.outline) { nav.push(.register) }
                    }
                    .padding(.top, 16)
                }
            }
            .padding(Spacing.screen)
            .padding(.top, 8 + statusBar)
        }
        .clipped() // HeroBox's pattern runs past its bottom edge
    }
}

private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

/// The Appearance row's value.
private func appearanceLabel(_ value: AppearanceSetting) -> String {
    switch value {
    case .light: "Light"
    case .dark: "Dark"
    case .system: "System"
    }
}

/// The Appearance dialog's choices.
private func appearanceChoice(_ value: AppearanceSetting) -> String {
    switch value {
    case .system: "Follow the phone"
    case .light: "Light"
    case .dark: "Dark"
    }
}

private func roleLabel(_ role: String?) -> String? {
    switch role {
    case Roles.admin: "Administrator"
    case Roles.developer: "Developer"
    case Roles.teacher: "Teacher"
    default: nil
    }
}

/// A group's heading in the Account list (blank: only the gap).
private struct AccountGroup: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 18)
            if !title.trimmed.isEmpty {
                Overline(text: title).padding(.horizontal, Spacing.screen).padding(.vertical, 6).accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One row of the Account list: icon, label, optional value, arrow.
private struct AccountEntry: View {
    let icon: Icon
    let label: String
    var trailing: String? = nil
    var danger = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                icon.image.font(.system(size: 20)).frame(width: 24, height: 24)
                    .foregroundStyle(danger ? Brand.danger : Scheme.primary)
                    .accessibilityHidden(true)
                Spacer().frame(width: 16)
                Text(label).textStyle(Typo.bodyLarge).foregroundStyle(danger ? Brand.danger : Scheme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    Text(trailing).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                    Spacer().frame(width: 8)
                }
                Icon.forward.image.font(.system(size: 14, weight: .medium)).frame(width: 18, height: 18)
                    .foregroundStyle(Scheme.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - edit profile

/// The profile form's state (Android's EditProfileViewModel + EditState).
@MainActor
@Observable
final class EditProfileModel {
    private(set) var profile: Load<Profile> = .loading
    private(set) var config: AppConfig?
    private(set) var saving = false
    private(set) var error: String?
    private(set) var saved = false
    private(set) var photoBusy = false
    /// This save completed the profile: the website's "Your profile is complete" step is shown.
    private(set) var justCompleted = false
    @ObservationIgnored private let app: AppContainer

    init(app: AppContainer) {
        self.app = app
        load()
    }

    func load() {
        Task {
            async let config = app.repo.appConfig().value
            let result = await app.auth.profile()
            self.config = await config
            profile = result.toLoad()
        }
    }

    /// Saves are one at a time: a second tap before the first answer is ignored.
    func save(_ update: ProfileUpdate) {
        if saving { return }
        let wasComplete = profile.value?.profileComplete == true
        saving = true
        error = nil
        saved = false
        Task {
            switch await app.auth.updateProfile(update) {
            case .success(let p):
                justCompleted = profileJustCompleted(wasComplete: wasComplete, isComplete: p.profileComplete)
                profile = .ready(p)
                saved = true
            case .failure(let e):
                error = e.message
            }
            saving = false
        }
    }

    /// One upload at a time.
    func photo(_ data: Data, mime: String) {
        if photoBusy { return }
        photoBusy = true
        error = nil
        Task {
            switch await app.auth.uploadPhoto(data, mime: mime) {
            case .success:
                if let p = await app.auth.profile().value { profile = .ready(p) }
            case .failure(let e):
                error = e.message
            }
            photoBusy = false
        }
    }
}

struct EditProfileScreen: View {
    var body: some View {
        DetailScaffold("Edit profile") {
            WithModel({ EditProfileModel(app: $0) }) { EditProfileContent(model: $0) }
        }
    }
}

private struct EditProfileContent: View {
    let model: EditProfileModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        LoadContent(state: model.profile, onRetry: { model.load() }) { profile in
            if model.justCompleted {
                ProfileCompleteStep { nav.switchTab(.courses) }
            } else {
                ProfileForm(profile: profile, model: model)
            }
        }
    }
}

private struct ProfileForm: View {
    let profile: Profile
    let model: EditProfileModel
    @State private var name: String
    @State private var father: String
    @State private var dob: String
    @State private var occupation: String
    @State private var address: String
    @State private var gender: String
    @State private var country: String
    @State private var whatsapp: String

    init(profile p: Profile, model: EditProfileModel) {
        profile = p
        self.model = model
        _name = State(initialValue: p.name ?? "")
        _father = State(initialValue: p.fatherName ?? "")
        _dob = State(initialValue: String((p.dateOfBirth ?? "").prefix(10)))
        _occupation = State(initialValue: p.occupation ?? "")
        _address = State(initialValue: p.address ?? "")
        _gender = State(initialValue: p.gender ?? "")
        _country = State(initialValue: p.whatsappCountry ?? model.config?.lookups.defaultCountryCode ?? "IN")
        _whatsapp = State(initialValue: p.whatsappLocal ?? "")
    }

    var body: some View {
        let countries = model.config?.lookups.countries ?? []
        let occupations = model.config?.lookups.occupations ?? []
        let selectedCountry = countries.first { $0.code == country }
        ScreenColumn(spacing: 14) {
            ProfilePhoto(profile: profile, gender: gender, busy: model.photoBusy) { model.photo($0, mime: $1) }
            if !profile.profileComplete { Banner("\(profileIncompleteTitle). \(profileIncompleteText)", tone: .warning) }
            if let error = model.error { Banner(error, tone: .danger) }
            if model.saved { Banner("Profile saved.", tone: .success) }
            OutlinedField(label: "Full name", text: $name, capitalization: .words)
            OutlinedField(label: "Father's name", text: $father, capitalization: .words)
            OutlinedField(
                label: "Date of birth (YYYY-MM-DD)",
                text: Binding(get: { dob }, set: { v in dob = String(v.filter { isDigitChar($0) || $0 == "-" }.prefix(10)) }),
                keyboard: .numbersAndPunctuation
            )
            Text("Gender").textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurface)
            HStack(spacing: 10) {
                ChoicePill(label: "Male", selected: gender == "MALE") { gender = "MALE" }
                ChoicePill(label: "Female", selected: gender == "FEMALE") { gender = "FEMALE" }
            }
            if !occupations.isEmpty {
                Dropdown(
                    value: occupations.first { $0.value == occupation }?.label ?? "Select",
                    options: occupations.map(\.label), label: "Occupation"
                ) { occupation = occupations[$0].value }
            }
            OutlinedField(label: "Address", text: $address, lines: 1...6)
            WeightedRow(weights: countries.isEmpty ? [1] : [1, 1.4], spacing: 10) {
                if !countries.isEmpty {
                    Dropdown(
                        value: selectedCountry.map { "\($0.flag) +\($0.dialCode)" } ?? country,
                        options: countries.map { "\($0.flag) \($0.name) (+\($0.dialCode))" }, label: "Country"
                    ) { country = countries[$0].code }
                }
                OutlinedField(
                    label: "WhatsApp",
                    text: Binding(get: { whatsapp }, set: { v in
                        whatsapp = String(v.filter(isDigitChar).prefix(selectedCountry?.localNumberMaxLength ?? 15))
                    }),
                    keyboard: .phonePad
                )
            }
            PrimaryButton("Save", loading: model.saving) {
                model.save(ProfileUpdate(
                    name: name.trimmed.nilIfBlank, fatherName: father.trimmed.nilIfBlank, dateOfBirth: dob.nilIfBlank,
                    occupation: occupation.nilIfBlank, address: address.trimmed.nilIfBlank, gender: gender.nilIfBlank,
                    country: whatsapp.trimmed.isEmpty ? nil : country, whatsapp: whatsapp.nilIfBlank
                ))
            }
        }
    }
}

/// The website's "Your profile is complete" notice with its "Browse courses" link.
private struct ProfileCompleteStep: View {
    let onBrowseCourses: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            AppCard {
                HStack(spacing: 8) {
                    Icon.checkCircle.image.font(.system(size: 20)).foregroundStyle(Brand.success)
                    Text(profileCompleteTitle).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                }
                Spacer().frame(height: 6)
                Text(profileCompleteText).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                Spacer().frame(height: 12)
                PrimaryButton("Browse courses", action: onBrowseCourses)
            }
        }
        .padding(Spacing.screen)
    }
}

// MARK: - payments

/// As on the website: receipts are not shown here; the academy e-mails them once issued.
private let receiptByEmail = "The academy e-mails your receipt once your payment is verified and the receipt is issued."

struct PaymentsScreen: View {
    var body: some View {
        DetailScaffold("Payments") {
            WithModel({ app in
                Loader<(PaymentHistory, [Enrollment])> {
                    switch await app.repo.paymentHistory() {
                    case .success(let history): .success((history, await app.repo.enrollments().value ?? []))
                    case .failure(let e): .failure(e)
                    }
                }
            }) { loader in
                LoadContent(state: loader.state, onRetry: { loader.load() }) { page in
                    PaymentsList(history: page.0, enrollments: page.1)
                }
            }
        }
    }
}

private struct PaymentsList: View {
    let history: PaymentHistory
    let enrollments: [Enrollment]

    var body: some View {
        let titles = Dictionary(enrollments.map { ($0.courseId, $0.course?.title ?? "") }, uniquingKeysWith: { _, last in last })
        if history.submissions.isEmpty && history.records.isEmpty {
            EmptyState(title: "No payments yet", message: "Fees you pay in the app or on the website appear here.")
        } else {
            let sorted = history.submissions.sorted { $0.createdAt > $1.createdAt }
            let awaiting = sorted.filter { $0.status.lowercased() == "pending_verification" }
            let settled = sorted.filter { $0.status.lowercased() != "pending_verification" }
            let others = history.records.filter { r in !history.submissions.contains { $0.paymentRecordId == r.id } }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Banner(receiptByEmail, tone: .info)
                    if !awaiting.isEmpty {
                        Overline(text: "Awaiting Approval").padding(.top, 4)
                        ForEach(awaiting) { SubmissionCard(submission: $0, titles: titles) }
                    }
                    if !settled.isEmpty { Overline(text: "Payment History").padding(.top, 4) }
                    ForEach(settled) { SubmissionCard(submission: $0, titles: titles) }
                    if !others.isEmpty { Overline(text: "Other payments recorded by the academy").padding(.top, 8) }
                    ForEach(others) { r in
                        AppCard {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(r.description ?? titleCase(r.paymentType ?? "Payment"))
                                        .textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                                    Text(formatDate(r.paidAt)).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(rupees(r.amountInrPaise)).textStyle(Typo.titleMedium).foregroundStyle(Scheme.primary)
                            }
                        }
                    }
                }
                .padding(Spacing.screen)
            }
        }
    }
}

private struct SubmissionCard: View {
    let submission: PaymentSubmission
    let titles: [String: String]

    var body: some View {
        let s = submission
        let (label, tone) = statusLabel(s.status, kind: .payment)
        let ref = s.upiTransactionId.flatMap { $0.trimmed.isEmpty || $0 == "FEE-WAIVER" ? nil : " · Ref \($0)" } ?? ""
        AppCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    if let title = titles[s.courseId], !title.trimmed.isEmpty { Overline(text: title) }
                    Text(s.label).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                    Text("\(formatDate(s.createdAt))\(ref)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(rupees(s.amountInrPaise)).textStyle(Typo.titleMedium).foregroundStyle(Scheme.primary)
                    StatusChip(label, tone: tone)
                }
            }
        }
    }
}

// MARK: - notifications

struct NotificationsScreen: View {
    var body: some View {
        WithModel({ app in
            PagedListModel<AppNotification> { page, _, filter in await app.repo.notifications(page: page, unreadOnly: filter == "unread") }
        }) { NotificationsContent(model: $0) }
    }
}

private struct NotificationsContent: View {
    let model: PagedListModel<AppNotification>
    @Environment(AppContainer.self) private var container
    @Environment(Navigator.self) private var nav

    var body: some View {
        let repo = container.repo
        // Unstructured tasks: opening a notification leaves this screen, which must not cancel marking it read.
        DetailScaffold("Notifications", actions: {
            TextButton("Mark all read") {
                Task {
                    _ = await repo.markAllRead()
                    model.refresh()
                }
            }
        }) {
            PagedListBody(model, searchHint: nil, emptyTitle: "You're all caught up", key: \.id, header: {
                HStack(spacing: 8) {
                    FilterChip(label: "All", selected: model.state.filter == nil) { model.filter(nil) }
                    FilterChip(label: "Unread", selected: model.state.filter == "unread") { model.filter("unread") }
                    Spacer()
                }
            }) { n in
                let unread = n.readAt == nil
                AppCard(color: unread ? Scheme.primaryContainer.opacity(0.4) : Scheme.surfaceContainerLowest, onClick: {
                    Task { _ = await repo.notification(n.id) }
                    nav.openLink(n.href)
                }) {
                    HStack(spacing: 0) {
                        if unread {
                            Circle().fill(Brand.goldSoft).frame(width: 8, height: 8).accessibilityLabel("Unread")
                            Spacer().frame(width: 8)
                        }
                        Text(n.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(relativeTime(n.createdAt)).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                    if let body = n.body {
                        Text(body).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant).padding(.top, 4)
                    }
                    if let related = relatedPageLabel(n.href) {
                        Text(related).textStyle(Typo.labelLarge).foregroundStyle(Scheme.primary).padding(.top, 6)
                    }
                }
            }
        }
    }
}

// MARK: - change password

struct ChangePasswordScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var submitter = Submitter()
    @State private var current = ""
    @State private var new = ""

    var body: some View {
        DetailScaffold("Change password") {
            ScreenColumn(spacing: 14) {
                if let result = submitter.result { Banner(result.message, tone: result.ok ? .success : .danger) }
                PasswordInput(label: "Current password", text: $current, contentType: .password)
                PasswordInput(label: "New password (at least 8 characters)", text: $new, contentType: .newPassword)
                Text("Other phones signed in to your account will be signed out.")
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                PrimaryButton("Change password", enabled: !current.isEmpty && new.count >= 8, loading: submitter.busy) {
                    let (from, to) = (current, new)
                    let auth = container.auth
                    submitter.submit {
                        switch await auth.changePassword(current: from, new: to) {
                        case .success: SubmitResult(message: "Password changed.", ok: true)
                        case .failure(let e): SubmitResult(message: e.message, ok: false)
                        }
                    }
                }
            }
        }
        .onChange(of: submitter.result) { _, result in
            if result?.ok == true { current = ""; new = "" }
        }
    }
}

/// Android's PasswordField: a secure outlined field with the show/hide eye, capped at 128 characters.
private struct PasswordInput: View {
    let label: String
    @Binding var text: String
    var contentType: UITextContentType = .password

    var body: some View {
        OutlinedField(
            label: label,
            text: Binding(get: { text }, set: { text = String($0.prefix(128)) }),
            secure: true, contentType: contentType, submitLabel: .done
        )
    }
}

// MARK: - delete account

private let accountDeleted = "Your account has been deleted. JazakAllahu khairan for learning with us."

struct DeleteAccountScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(Navigator.self) private var nav
    @State private var submitter = Submitter()
    // Whether the account has a password decides what confirms the deletion; guessing "yes" when the profile didn't
    // load left a Google-only user with a password field they couldn't fill.
    @State private var hasPassword: Load<Bool> = .loading
    @State private var attempt = 0
    @State private var password = ""
    @State private var confirm = ""

    var body: some View {
        let busy = submitter.busy
        let done = submitter.result?.ok == true
        DetailScaffold("Delete account") {
            ScreenColumn(spacing: 14) {
                if done {
                    MessageState(icon: .checkCircle, title: "Account deleted", message: accountDeleted, action: "Close") { nav.switchTab(.home) }
                } else {
                    Banner("This permanently deletes your account. It cannot be undone.", tone: .danger, icon: .deleteForever)
                    Text("What happens").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                    ForEach(deletionFacts, id: \.self) { fact in
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("•  ").textStyle(Typo.bodyLarge).foregroundStyle(Brand.gold)
                            Text(fact).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                        }
                    }
                    if let error = submitter.result.flatMap({ $0.ok ? nil : $0.message }) { Banner(error, tone: .danger) }
                    switch hasPassword {
                    case .loading: LoadingBox(height: 60)
                    case .failed(let message): ErrorState(message: message) { attempt += 1 }
                    case .ready(true): PasswordInput(label: "Your password", text: $password)
                    case .ready(false):
                        OutlinedField(label: "Type DELETE to confirm", text: $confirm, capitalization: .characters, autocorrect: false)
                    }
                    Button { delete() } label: {
                        Text(busy ? "Deleting…" : "Delete my account").textStyle(Typo.labelLarge)
                            .padding(.horizontal, 24)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(FilledStyle(background: Brand.danger, foreground: .white, radius: 26))
                    .disabled(!canDelete)
                }
            }
        }
        .task(id: attempt) {
            hasPassword = .loading
            hasPassword = await container.auth.profile().map(\.hasPassword).toLoad()
        }
    }

    private var canDelete: Bool {
        guard !submitter.busy, case .ready(let withPassword) = hasPassword else { return false }
        return withPassword ? !password.isEmpty : confirm == "DELETE"
    }

    private func delete() {
        let pass = password.isEmpty ? nil : password
        let typed = confirm.isEmpty ? nil : confirm
        let auth = container.auth
        let toaster = container.toaster
        let nav = nav
        submitter.submit {
            switch await auth.deleteAccount(password: pass, confirm: typed) {
            case .success:
                // The session is cleared by now, which starts the app over as a guest (this screen included), so the
                // message is said as a toast too. The cart empties itself on sign-out.
                toaster.show(accountDeleted, long: true)
                nav.switchTab(.home)
                return SubmitResult(message: accountDeleted, ok: true)
            case .failure(let e):
                return SubmitResult(message: e.message, ok: false)
            }
        }
    }
}

private let deletionFacts = [
    "Your name, e-mail, photo, contact details and password are removed, and you are signed out everywhere.",
    "Applications still waiting for the academy are withdrawn.",
    "Receipts and fee history are kept without your personal details, because the academy must keep financial records.",
    "You can register again later with the same e-mail address.",
]

// MARK: - about

struct AboutScreen: View {
    @Environment(Navigator.self) private var nav

    var body: some View {
        DetailScaffold("About") {
            ScrollView {
                VStack(spacing: 0) {
                    HeroBox {
                        VStack(spacing: 0) {
                            Image("Logo").resizable().scaledToFit()
                                .frame(width: 84, height: 84).background(Color.white).clipShape(Circle())
                                .accessibilityHidden(true)
                            Spacer().frame(height: 14)
                            Text("Darse Quran Academy").textStyle(Typo.headlineSmall).foregroundStyle(Brand.onHero)
                            ArabicText(text: "خَيْرُكُمْ مَنْ تَعَلَّمَ الْقُرْآنَ وَعَلَّمَهُ", color: Brand.goldSoft, size: 22)
                            Text("The best among you are those who learn the Quran and teach it.")
                                .textStyle(Typo.bodySmall).foregroundStyle(Brand.onHero.opacity(0.85))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(28)
                    }
                    .clipped() // HeroBox's pattern runs past its bottom edge
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Darse Quran Academy teaches the Quran, Tajweed, Islamic jurisprudence, Hadith and the Arabic language with qualified teachers, online and in person, for students of every age.")
                            .textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                        PrimaryButton("Meet our teachers") { nav.push(.teachers) }
                        SecondaryButton("Visit the website") { openWeb("/about") }
                    }
                    .padding(Spacing.screen)
                }
            }
        }
    }
}
