import Foundation
import Observation

/// Something the student should do now, shown at the top of Home (Android's ActionCard).
struct ActionCard: Equatable, Sendable {
    enum Kind: Sendable { case payEnrollment, payCourseFee, underReview, completeProfile, verifyEmail }

    let kind: Kind
    let title: String
    let message: String
    var courseId: String? = nil
    var courseTitle: String? = nil
}

// MARK: - resending the verification e-mail

/// The website's VerificationBanner states: idle, sending, or the answer to the last resend.
///
/// Home's own copy of Android's ui/account/ResendState.kt (the Account area owns the original); named apart so the two
/// can live in one module.
struct HomeResendState: Equatable, Sendable {
    var sending = false
    var sent = false
    var message: String? = nil
}

let homeVerificationSent =
    "Verification email sent! Please check your Inbox. If you don't see it, check your Spam/Junk folder as well."

/// The state after a resend answered with [result].
func homeResendOutcome<T>(_ result: ApiResult<T>) -> HomeResendState {
    switch result {
    case .success: HomeResendState(sent: true, message: homeVerificationSent)
    case .failure(let e): HomeResendState(message: e.message.trimmed.isEmpty ? "Failed to resend verification email." : e.message)
    }
}

/// The button's words, as on the website.
func homeResendLabel(_ state: HomeResendState) -> String {
    if state.sending { return "Sending..." }
    if state.sent { return "Sent" }
    return "Resend Verification Email"
}

// MARK: - the action cards

/// The cards a student sees for their account, courses and payments (Android's HomeViewModel.loadNow, buildList).
func homeActions(profile: Profile?, enrollments: [Enrollment], submissions: [PaymentSubmission], today: YearMonth = .current()) -> [ActionCard] {
    var actions: [ActionCard] = []
    if let me = profile, me.emailVerified == nil {
        actions.append(ActionCard(kind: .verifyEmail, title: "Verify your e-mail", message: "Check your inbox for the link. You need it to enrol and pay."))
    }
    if let me = profile, !me.profileComplete {
        actions.append(ActionCard(kind: .completeProfile, title: "Complete your profile", message: "Your details are needed before you can enrol in a course."))
    }
    let pending = submissions.filter { $0.status == "pending_verification" }
    for e in enrollments {
        guard let course = e.course else { continue }
        let pendingHere = pending.filter { $0.courseId == e.courseId }
        if e.status == "awaiting_enrollment_fee", !pendingHere.contains(where: { $0.paymentType == "enrollment" }) {
            actions.append(ActionCard(
                kind: .payEnrollment, title: "Pay the enrollment fee", message: "\(course.title) · \(rupees(course.priceInrPaise))",
                courseId: course.id, courseTitle: course.title
            ))
        }
        if monthlyFeeDue(e, submissions, today: today) {
            actions.append(ActionCard(
                kind: .payCourseFee, title: "\(feePeriod(today)) fee is due", message: "\(course.title) · \(rupees(course.monthlyFeeInrPaise))",
                courseId: course.id, courseTitle: course.title
            ))
        }
    }
    if !pending.isEmpty {
        actions.append(ActionCard(
            kind: .underReview, title: "Payment under review",
            message: pending.count == 1 ? "The academy will confirm it shortly." : "\(pending.count) payments are being verified."
        ))
    }
    return actions
}

// MARK: - the model

/// Home's state (Android's HomeViewModel + HomeState).
///
/// The newest load wins: a slower one started for the previous session must not overwrite it (or its user's data). A
/// token refresh saves a new session for the same user; only a different user (or none) reloads.
@MainActor
@Observable
final class HomeModel {
    private(set) var loading: Bool
    private(set) var refreshing = false
    private(set) var error: String?
    private(set) var content: HomeResponse?
    private(set) var session: Session?
    private(set) var enrollments: [Enrollment] = []
    private(set) var actions: [ActionCard] = []
    private(set) var unread = 0
    private(set) var resend = HomeResendState()

    @ObservationIgnored private let repo: AcademyRepository
    @ObservationIgnored private let auth: AuthRepository
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadedFor: String?

    init(repo: AcademyRepository, auth: AuthRepository) {
        self.repo = repo
        self.auth = auth
        let cached = repo.cachedHome()
        content = cached
        loading = cached == nil
        session = auth.sessionStore.current
        loadedFor = session?.user.id
        auth.sessionStore.observe { [weak self] value in
            Task { @MainActor in self?.sessionChanged(value) }
        }
        load()
    }

    private func sessionChanged(_ value: Session?) {
        session = value
        if value?.user.id != loadedFor {
            loadedFor = value?.user.id
            load()
        }
    }

    /// Pull to refresh: waits until the whole load is back.
    func refresh() async {
        await load(refreshing: true).value
    }

    func reload() { load() }

    /// Sends the verification link again; once sent, the button stays "Sent" (as on the website).
    func resendVerification() {
        guard let email = auth.sessionStore.current?.user.email else { return }
        if resend.sending || resend.sent { return }
        resend = HomeResendState(sending: true)
        let auth = self.auth
        Task {
            let result = await auth.resendVerification(email: email)
            resend = homeResendOutcome(result)
        }
    }

    @discardableResult
    private func load(refreshing: Bool = false) -> Task<Void, Never> {
        task?.cancel()
        generation += 1
        let gen = generation
        let t = Task { [weak self] in _ = await self?.loadNow(refreshing: refreshing, gen: gen) }
        task = t
        return t
    }

    private func loadNow(refreshing: Bool, gen: Int) async {
        self.refreshing = refreshing
        error = nil
        let repo = self.repo
        let auth = self.auth
        let signedIn = auth.sessionStore.current != nil
        async let home = repo.home()
        async let enrollments: [Enrollment] = signedIn ? (await repo.enrollments().value ?? []) : []
        async let history: PaymentHistory? = signedIn ? await repo.paymentHistory().value : nil
        async let profile: Profile? = signedIn ? await auth.profile().value : nil
        async let unread: Int = signedIn ? (await repo.notifications(page: 1, unreadOnly: true).value?.unreadCount ?? 0) : 0

        // A cold start shows the last run's home screen while the new one loads.
        if content == nil, let saved = repo.lastHome() {
            content = saved
            loading = false
        }
        // The page shows as soon as its content arrives; the student's own cards follow when their calls answer.
        let homeResult = await home
        guard gen == generation else { return }
        loading = false
        switch homeResult {
        case .success(let value): content = value
        case .failure(let e): if content == nil, !e.cancelled { error = e.message }
        }

        let list = await enrollments
        let submissions = (await history)?.submissions ?? []
        let me = await profile
        let count = await unread
        guard gen == generation else { return }
        self.refreshing = false
        self.enrollments = list
        self.actions = homeActions(profile: me, enrollments: list, submissions: submissions)
        self.unread = count
    }
}
