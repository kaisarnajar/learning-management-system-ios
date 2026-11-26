import Observation
import SwiftUI

// MARK: - tab

/// The signed-in user's courses; the catalogue is a separate [PagedListModel] (Android's CoursesViewModel).
@MainActor
@Observable
final class CoursesModel {
    private(set) var signedIn: Bool
    private(set) var mine: Load<[Enrollment]> = .loading
    private(set) var refreshing = false
    let catalogue: PagedListModel<Course>

    @ObservationIgnored private let repo: AcademyRepository
    @ObservationIgnored private let auth: AuthRepository
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var mineTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(repo: AcademyRepository, auth: AuthRepository) {
        self.repo = repo
        self.auth = auth
        catalogue = PagedListModel { page, query, _ in await repo.courses(page: page, search: query) }
        userId = auth.sessionStore.current?.user.id
        signedIn = userId != nil
        loadMine()
        // A token refresh saves a new session for the same user: only a different user (or none) needs a reload.
        auth.sessionStore.observe(owner: self) { [weak self] session in
            let id = session?.user.id
            Task { @MainActor in self?.userChanged(id) }
        }
    }

    private func userChanged(_ id: String?) {
        signedIn = id != nil
        guard id != userId else { return }
        userId = id
        loadMine()
    }

    /// Coming back from a course: its status may have changed.
    func reloadMine() { loadMine() }

    /// Pull to refresh: waits for the courses.
    func refresh() async {
        refreshing = true
        await loadMine().value
    }

    /// The newest load wins: one started for the previous session must not overwrite this one's courses.
    @discardableResult
    private func loadMine() -> Task<Void, Never> {
        mineTask?.cancel()
        generation += 1
        let gen = generation
        let signedIn = auth.sessionStore.current != nil
        let task = Task { [weak self, repo] in
            let mine: Load<[Enrollment]> = signedIn ? await repo.enrollments().toLoad() : .ready([])
            guard let self, gen == self.generation else { return }
            self.mine = mine
            self.refreshing = false
        }
        mineTask = task
        return task
    }
}

struct CoursesScreen: View {
    var body: some View {
        WithModel({ CoursesModel(repo: $0.repo, auth: $0.auth) }) { model in CoursesContent(model: model) }
    }
}

private struct CoursesContent: View {
    let model: CoursesModel
    @Environment(Navigator.self) private var nav
    @State private var tab = 0

    var body: some View {
        let showMine = model.signedIn && tab == 0
        VStack(spacing: 0) {
            TabTopBar("Courses")
            if model.signedIn {
                SecondaryTabRow(tabs: ["My courses", "Catalogue"], selected: $tab)
            }
            if showMine {
                MyCoursesList(model: model, onBrowse: { tab = 1 })
            } else {
                PagedListBody(model.catalogue, searchHint: "Search courses", emptyTitle: "No courses found", key: { $0.id }) { course in
                    CourseCard(course: course) { nav.push(.course(id: course.id)) }
                }
            }
        }
        .background(Scheme.background)
        .reloadOnReturn { model.reloadMine() }
    }
}

private struct MyCoursesList: View {
    let model: CoursesModel
    let onBrowse: () -> Void
    @Environment(Navigator.self) private var nav

    var body: some View {
        ScrollView {
            switch model.mine {
            case .loading: SkeletonList()
            case .failed(let message): ErrorState(message: message) { model.reloadMine() }
            case .ready(let mine):
                if mine.isEmpty {
                    EmptyState(
                        title: "No courses yet",
                        message: "Find a course in the catalogue and apply. It will appear here.",
                        action: "Browse the catalogue",
                        onAction: onBrowse
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(mine) { e in EnrollmentCard(enrollment: e) }
                    }
                    .padding(Spacing.screen)
                }
            }
        }
        .refreshable { await model.refresh() }
        .background(Scheme.background)
    }
}

private struct EnrollmentCard: View {
    let enrollment: Enrollment
    @Environment(Navigator.self) private var nav

    var body: some View {
        let e = enrollment
        let (label, tone) = statusLabel(e.status)
        let open = EnrollmentStatus.opensLearn(e.status)
        AppCard(onClick: {
            if open { nav.push(.learn(courseId: e.courseId, title: e.course?.title ?? "Course")) } else { nav.push(.course(id: e.courseId)) }
        }) {
            HStack {
                StatusChip(label, tone: tone)
                Spacer()
                if let roll = e.rollNumber {
                    Text(rollNumberLabel(roll)).textStyle(Typo.labelMedium).foregroundStyle(Brand.gold)
                }
            }
            Spacer().frame(height: 10)
            Text(e.course?.title ?? "Course").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
            if let teacher = e.course?.teacher {
                Spacer().frame(height: 8)
                HStack(spacing: 8) {
                    Avatar(name: teacher.name, image: teacher.imageUrl, size: 28)
                    Text(teacher.name).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                }
            }
            ForEach(Array(enrollmentNotes(e).enumerated()), id: \.offset) { i, note in
                let refusal = i == 0 && e.status == EnrollmentStatus.rejected // the website shows it in red
                Spacer().frame(height: 6)
                Text(note).textStyle(Typo.bodySmall).foregroundStyle(refusal ? Scheme.error : Scheme.onSurfaceVariant)
            }
        }
    }
}

/// A catalogue card: green band with category and level, then title, summary, teacher and fees (Android's CourseCard).
struct CourseCard: View {
    let course: Course
    let onClick: () -> Void

    var body: some View {
        AppCard(padding: 0, onClick: onClick) {
            HeroBox {
                HStack {
                    Overline(text: course.category.trimmed.isEmpty ? "Course" : course.category, color: Brand.goldSoft)
                    Spacer()
                    if !course.level.trimmed.isEmpty {
                        Text(course.level).textStyle(Typo.labelMedium).foregroundStyle(Brand.mint)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 70)
            }
            .clipped() // HeroBox's pattern runs past its bottom edge
            VStack(alignment: .leading, spacing: 0) {
                Text(course.title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface).multilineTextAlignment(.leading)
                Spacer().frame(height: 6)
                Text(plainText(course.description))
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    .lineLimit(2).truncationMode(.tail).multilineTextAlignment(.leading)
                if let t = course.teacher {
                    Spacer().frame(height: 12)
                    HStack(spacing: 10) {
                        Avatar(name: t.name, image: t.imageUrl, size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.name).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                            Text(t.specialization).textStyle(Typo.bodySmall).foregroundStyle(Brand.gold).lineLimit(1)
                        }
                    }
                }
                Spacer().frame(height: 12)
                WeightedRow(weights: [1, 1.4]) {
                    FeeBlock(label: "Enrollment", value: course.priceInrPaise > 0 ? rupees(course.priceInrPaise) : "Free")
                    FeeBlock(label: "Course fee", value: courseFeeText(course))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FeeBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
            Text(value).textStyle(Typo.titleMedium).foregroundStyle(Scheme.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row whose children share the width by weight, bottom-aligned (Compose's Row with Modifier.weight).
struct WeightedRow: Layout {
    let weights: [CGFloat]
    var spacing: CGFloat = 0

    private func widths(_ total: CGFloat, _ count: Int) -> [CGFloat] {
        let sum = (0..<count).map(weight).reduce(0, +)
        let free = max(0, total - spacing * CGFloat(max(0, count - 1)))
        return (0..<count).map { free * weight($0) / max(sum, 1) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let ws = widths(width, subviews.count)
        let height = subviews.enumerated().map { i, v in v.sizeThatFits(ProposedViewSize(width: ws[i], height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ws = widths(bounds.width, subviews.count)
        var x = bounds.minX
        for (i, v) in subviews.enumerated() {
            let size = v.sizeThatFits(ProposedViewSize(width: ws[i], height: nil))
            v.place(at: CGPoint(x: x, y: bounds.maxY - size.height), proposal: ProposedViewSize(width: ws[i], height: size.height))
            x += ws[i] + spacing
        }
    }

    private func weight(_ i: Int) -> CGFloat { i < weights.count ? weights[i] : 1 }
}

// MARK: - detail

let enrollRequested = "Enrollment requested. The academy will review it soon."
private let courseVerificationSent = "Verification e-mail sent to"
private let feesNote = "Fees are set by the academy for each course. Paid courses require an enrollment fee " +
    "before access is granted; monthly fees are paid from your profile after enrollment is active."

/// One course, who teaches it, what it costs, and the student's single next step (Android's CourseDetailViewModel).
@MainActor
@Observable
final class CourseDetailModel {
    /// Where the screen goes after an application, once it has been answered.
    enum AfterApply: Equatable { case pay, completeProfile }

    let courseId: String
    private(set) var state: Load<CourseDetailResponse> = .loading
    private(set) var signedIn: Bool
    private(set) var busy = false
    private(set) var message: String?
    /// The signed-in user's profile: whether it is complete and the e-mail verified decide the enrol button.
    private(set) var profile: Profile?
    /// Set when the answer to an application sends the student on; the screen goes there and calls [consumeNext].
    private(set) var next: AfterApply?

    @ObservationIgnored private let repo: AcademyRepository
    @ObservationIgnored private let auth: AuthRepository
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(repo: AcademyRepository, auth: AuthRepository, courseId: String) {
        self.repo = repo
        self.auth = auth
        self.courseId = courseId
        userId = auth.sessionStore.current?.user.id
        signedIn = userId != nil
        load()
        // Enrolled or not, and what to pay, depend on who is signed in: signing in from "Sign in to apply" must show it.
        auth.sessionStore.observe(owner: self) { [weak self] session in
            let id = session?.user.id
            Task { @MainActor in self?.userChanged(id) }
        }
    }

    private func userChanged(_ id: String?) {
        signedIn = id != nil
        guard id != userId else { return }
        userId = id
        load()
    }

    /// Reloads in place (the page stays up meanwhile); the newest load wins.
    @discardableResult
    func load() -> Task<Void, Never> {
        loadTask?.cancel()
        generation += 1
        let gen = generation
        let signedIn = auth.sessionStore.current != nil
        let task = Task { [weak self, repo, auth, courseId] in
            async let me: Profile? = signedIn ? auth.profile().value : nil
            let course = await repo.course(courseId)
            let profile = await me
            guard let self, gen == self.generation, !(course.error?.cancelled ?? false) else { return }
            self.state = course.toLoad()
            self.profile = profile
        }
        loadTask = task
        return task
    }

    /// "Verify your email to enroll": sends the verification e-mail again.
    func resendVerification() {
        guard let email = profile?.email, !busy else { return }
        busy = true
        Task {
            switch await auth.resendVerification(email: email) {
            case .success: message = "\(courseVerificationSent) \(email). Open the link in it, then come back to enroll."
            case .failure(let e): message = e.message
            }
            busy = false
        }
    }

    func consumeNext() { next = nil }

    /// Applies; free courses wait for approval, paid ones continue to the enrollment-fee payment.
    /// One application per tap: a second tap (even in the same frame) is ignored while the first is sent.
    func apply() {
        if busy { return }
        busy = true
        message = nil
        Task {
            await sendApplication()
            busy = false
        }
    }

    private func sendApplication() async {
        switch await repo.enroll(courseId) {
        case .success(let r):
            load()
            if r.requiresEnrollmentFee == true { next = .pay } else { message = enrollRequested }
        case .failure(let e):
            if e.message.range(of: "complete your profile", options: .caseInsensitive) != nil { next = .completeProfile }
            message = e.message
        }
    }
}

struct CourseDetailScreen: View {
    let courseId: String
    var body: some View {
        WithModel({ CourseDetailModel(repo: $0.repo, auth: $0.auth, courseId: courseId) }) { model in
            CourseDetailContent(model: model)
        }
    }
}

private struct CourseDetailContent: View {
    let model: CourseDetailModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                VStack(alignment: .leading, spacing: 0) { headerBack; LoadingBox() }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 0) { headerBack; ErrorState(message: message) { model.load() }; Spacer() }
            case .ready(let detail):
                ready(detail)
            }
        }
        .background(Scheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // Back from paying the enrollment fee (or anything else): the enrollment may have moved on, e.g. to "under
        // review", and the page must not keep offering the payment just made.
        .reloadOnReturn { model.load() }
        .afterApply(model, title: model.state.value?.course.title)
    }

    private var headerBack: some View {
        IconButton(.back, label: "Back") { nav.pop() }
    }

    private func ready(_ detail: CourseDetailResponse) -> some View {
        let course = detail.course
        return GeometryReader { outer in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(detail, topInset: outer.safeAreaInsets.top)
                    VStack(alignment: .leading, spacing: 16) {
                        if let message = model.message {
                            let good = message == enrollRequested || message.hasPrefix(courseVerificationSent)
                            Banner(message, tone: good ? .success : .warning)
                        }
                        if !detail.enrollmentOpen && detail.enrollment == nil {
                            Banner(enrollmentClosedMessage(course.status), tone: .warning)
                        }
                        AppCard {
                            InfoRow(icon: .calendar, label: "Starts", value: course.startDate.trimmed.isEmpty ? "To be announced" : formatCalendarDate(course.startDate))
                            InfoRow(icon: .schedule, label: "Duration", value: course.duration.trimmed.isEmpty ? "—" : course.duration)
                            InfoRow(icon: .signal, label: "Level", value: course.level.trimmed.isEmpty ? "All levels" : course.level)
                            InfoRow(icon: .payments, label: "Enrollment fee", value: course.priceInrPaise > 0 ? rupees(course.priceInrPaise) : "Free")
                            InfoRow(icon: .payments, label: "Course fee", value: courseFeeText(course), last: true)
                            Spacer().frame(height: 8)
                            Text(feesNote).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                        }
                        if let t = course.teacher {
                            AppCard(onClick: { nav.push(.teacher(id: t.id)) }) {
                                Overline(text: "Your teacher")
                                Spacer().frame(height: 10)
                                HStack(spacing: 14) {
                                    Avatar(name: t.name, image: t.imageUrl, size: 52)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(t.name).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                                        Text(t.specialization).textStyle(Typo.bodySmall).foregroundStyle(Brand.gold)
                                    }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About this course").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                            let about = plainText(course.description)
                            Text(about.isEmpty ? "Details will be shared by the academy." : about)
                                .textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                        }
                    }
                    .padding(Spacing.screen)
                }
            }
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CourseActionBar(detail: detail, gate: enrollGate(signedIn: model.signedIn, profile: model.profile), busy: model.busy, actions: actions(course))
            }
        }
    }

    private func hero(_ detail: CourseDetailResponse, topInset: CGFloat) -> some View {
        let course = detail.course
        return HeroBox {
            VStack(alignment: .leading, spacing: 0) {
                IconButton(.back, label: "Back", tint: Brand.onHero) { nav.pop() }
                VStack(alignment: .leading, spacing: 0) {
                    Overline(text: course.category.trimmed.isEmpty ? "Course" : course.category, color: Brand.goldSoft)
                    Spacer().frame(height: 6)
                    Text(course.title).textStyle(Typo.headlineMedium).foregroundStyle(Brand.onHero)
                    Spacer().frame(height: 12)
                    HStack(spacing: 8) {
                        if !course.level.trimmed.isEmpty { StatusChip(course.level, tone: .success) }
                        if let enrollment = detail.enrollment {
                            let (label, tone) = statusLabel(enrollment.status)
                            StatusChip(label, tone: tone)
                        }
                    }
                }
                .padding(.horizontal, Spacing.screen)
            }
            .padding(.top, topInset)
            .padding(.bottom, 24)
        }
        .clipped() // HeroBox's pattern runs past its bottom edge
    }

    private func actions(_ course: Course) -> EnrollActions {
        EnrollActions(
            signIn: { nav.push(.signIn) },
            apply: { model.apply() },
            pay: { nav.push(.pay(courseId: model.courseId, type: "enrollment", title: course.title)) },
            open: { nav.push(.learn(courseId: model.courseId, title: course.title)) },
            completeProfile: { nav.push(.editProfile) },
            verifyEmail: { model.resendVerification() }
        )
    }
}

private struct InfoRow: View {
    let icon: Icon
    let label: String
    let value: String
    var last = false

    var body: some View {
        HStack(spacing: 12) {
            icon.image.font(.system(size: 17)).foregroundStyle(Brand.gold).frame(width: 20, height: 20)
            Text(label).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
        if !last { Rectangle().fill(Brand.outlineSoft).frame(height: 1) }
    }
}

/// The single next step for this person and this course.
private struct CourseActionBar: View {
    let detail: CourseDetailResponse
    let gate: EnrollGate
    let busy: Bool
    let actions: EnrollActions

    var body: some View {
        let button = enrollButton(detail, gate: gate, actions: actions)
        PrimaryButton(button.label, enabled: button.enabled, loading: busy, action: button.action)
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                Rectangle()
                    .fill(Scheme.surfaceContainerLowest.shadow(.drop(color: Brand.cardShadow, radius: 8, x: 0, y: -2)))
                    .ignoresSafeArea(edges: .bottom)
            )
    }
}

// MARK: - enrol rules

/// The website's message for a course that takes no new students (getCourseEnrollmentClosedMessage).
func enrollmentClosedMessage(_ status: String) -> String {
    switch status {
    case "DRAFT": "This course is not available."
    case "ON_HOLD": "Enrollment is temporarily on hold for this course."
    case "COMPLETED": "This course has completed. New enrollments are closed."
    case "COMING_SOON": "Enrollment has not started yet. Coming soon!"
    default: "Enrollment is not available for this course."
    }
}

/// What stands between this person and requesting enrollment, checked in the website's order.
enum EnrollGate { case signIn, completeProfile, verifyEmail, ready }

/// The profile still loading counts as ready: the server checks again when the request is sent.
func enrollGate(signedIn: Bool, profile: Profile?) -> EnrollGate {
    if !signedIn { return .signIn }
    guard let profile else { return .ready }
    if !profile.profileComplete { return .completeProfile }
    if profile.emailVerified == nil { return .verifyEmail }
    return .ready
}

struct EnrollActions {
    let signIn: () -> Void
    let apply: () -> Void
    let pay: () -> Void
    let open: () -> Void
    let completeProfile: () -> Void
    let verifyEmail: () -> Void

    static var none: EnrollActions { EnrollActions(signIn: {}, apply: {}, pay: {}, open: {}, completeProfile: {}, verifyEmail: {}) }
}

/// The enrol button's label and whether it acts: the website's CourseEnrollButton, state by state.
func enrollButton(_ detail: CourseDetailResponse, gate: EnrollGate, actions: EnrollActions) -> (label: String, action: () -> Void, enabled: Bool) {
    // A rejected request behaves like none: the student may request again.
    let enrollment = detail.enrollment.flatMap { $0.status != "rejected" ? $0 : nil }
    let nothing: () -> Void = {}
    if let enrollment {
        switch enrollment.status {
        case "completed": return ("Completed — Open course", actions.open, true)
        case "active": return ("Enrolled — Open course", actions.open, true)
        case "pending_approval": return ("Awaiting enrollment approval", nothing, false)
        case "awaiting_enrollment_fee":
            return enrollment.enrollmentFeePending
                ? ("Awaiting payment verification", nothing, false)
                : ("Pay enrollment fee · \(rupees(detail.course.priceInrPaise))", actions.pay, true)
        default: return ("Open course", actions.open, true)
        }
    }
    if !detail.enrollmentOpen { return ("Not accepting students", nothing, false) }
    switch gate {
    case .signIn: return ("Sign in to request enrollment", actions.signIn, true)
    case .completeProfile: return ("Complete profile to enroll", actions.completeProfile, true)
    case .verifyEmail: return ("Verify your email to enroll", actions.verifyEmail, true)
    case .ready: return ("Request enrollment", actions.apply, true)
    }
}
