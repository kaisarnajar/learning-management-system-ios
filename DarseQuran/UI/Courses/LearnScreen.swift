import Observation
import SwiftUI

/// An enrolled course: its announcements, attendance, grades and fees (Android's LearnViewModel).
@MainActor
@Observable
final class LearnModel {
    let courseId: String
    private(set) var updates: Load<CourseAnnouncementsResponse> = .loading
    private(set) var attendance: Load<CourseAttendance?> = .loading
    private(set) var grades: Load<CourseGrades?> = .loading
    private(set) var fees: Load<PaymentHistory> = .loading
    /// This course's enrollment (status, fee), which decides whether a course fee can be paid from here.
    private(set) var enrollment: Enrollment?

    @ObservationIgnored private let repo: AcademyRepository

    init(repo: AcademyRepository, courseId: String) {
        self.repo = repo
        self.courseId = courseId
        loadAll()
    }

    func loadAll() {
        let repo = repo, courseId = courseId
        Task { [weak self] in let r = await repo.courseAnnouncements(courseId); self?.updates = r.toLoad() }
        Task { [weak self] in let r = await repo.attendance(courseId); self?.attendance = r.toLoad() }
        Task { [weak self] in let r = await repo.grades(courseId); self?.grades = r.toLoad() }
        Task { [weak self] in let r = await repo.paymentHistory(); self?.fees = r.toLoad() }
        Task { [weak self] in
            if let list = await repo.enrollments().value { self?.enrollment = list.first { $0.courseId == courseId } }
        }
    }
}

struct LearnScreen: View {
    let courseId: String
    let title: String
    var body: some View {
        WithModel({ LearnModel(repo: $0.repo, courseId: courseId) }) { model in LearnContent(model: model, title: title) }
    }
}

private struct LearnContent: View {
    let model: LearnModel
    let title: String
    @Environment(Navigator.self) private var nav
    @State private var tab = 0

    var body: some View {
        DetailScaffold(title, actions: {
            TextButton("Details") { nav.push(.course(id: model.courseId)) }
        }) {
            VStack(spacing: 0) {
                PrimaryScrollableTabRow(tabs: ["Announcements", "Attendance", "Grades", "Fees"], selected: $tab)
                Group {
                    switch tab {
                    case 0: UpdatesTab(model: model)
                    case 1: AttendanceTab(model: model)
                    case 2: GradesTab(model: model)
                    default: FeesTab(model: model) { nav.push(.pay(courseId: model.courseId, type: "course", title: title)) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .reloadOnReturn { model.loadAll() }
    }
}

/// A scrolling list with the screen padding, as Android's LazyColumn(contentPadding = 20.dp).
private struct TabList<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) { content() }
                .padding(Spacing.screen)
        }
    }
}

// MARK: - announcements

private struct UpdatesTab: View {
    let model: LearnModel

    var body: some View {
        LoadContent(state: model.updates, onRetry: model.loadAll) { data in
            if data.courseWide.isEmpty && data.personal.isEmpty {
                EmptyState(title: "No announcements yet. Check back later.")
            } else {
                TabList(spacing: 12) {
                    if !data.personal.isEmpty {
                        SectionHeading(title: "For you", subtitle: "Private messages from your instructor")
                        ForEach(data.personal) { AnnouncementItem(item: $0, personal: true) }
                        Spacer().frame(height: 8)
                    }
                    if !data.courseWide.isEmpty {
                        SectionHeading(title: "Course-wide", subtitle: "Visible to everyone in this course")
                        ForEach(data.courseWide) { AnnouncementItem(item: $0, personal: false) }
                    }
                }
            }
        }
    }
}

private struct SectionHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface).accessibilityAddTraits(.isHeader)
            Text(subtitle).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
        }
    }
}

private struct AnnouncementItem: View {
    let item: CourseAnnouncement
    let personal: Bool
    @Environment(AppContainer.self) private var app

    var body: some View {
        AppCard(color: personal ? Scheme.secondaryContainer.opacity(0.45) : Scheme.surfaceContainerLowest) {
            HStack(spacing: 0) {
                if personal {
                    Icon.lock.image.font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.gold).frame(width: 14, height: 14)
                    Spacer().frame(width: 6)
                    Text("For you only").textStyle(Typo.labelMedium).foregroundStyle(Brand.gold)
                    Text(" · ").textStyle(Typo.labelMedium).foregroundStyle(Brand.gold)
                }
                Text(item.authorName.trimmed.isEmpty ? "Academy" : item.authorName)
                    .textStyle(Typo.labelMedium).foregroundStyle(Brand.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(relativeTime(item.createdAt)).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
            }
            Spacer().frame(height: 6)
            Text(item.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
            Spacer().frame(height: 4)
            Text(item.body).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
            if let category = item.category {
                Spacer().frame(height: 8)
                StatusChip(announcementCategory(category), tone: .neutral)
            }
            if let path = item.attachmentPath {
                Spacer().frame(height: 8)
                AssistChip(label: item.attachmentName ?? "Attachment", icon: .attachment) {
                    let name = item.attachmentName ?? "attachment"
                    app.toaster.show("Opening \(name)…")
                    Task {
                        if let failure = await downloadAndOpen(app.client, path: path, fileName: name) { app.toaster.show(failure) }
                    }
                }
            }
        }
    }
}

/// Material 3's AssistChip: 32pt, outlined, a leading icon in the primary colour.
private struct AssistChip: View {
    let label: String
    let icon: Icon
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.input)
        Button(action: action) {
            HStack(spacing: 8) {
                icon.image.font(.system(size: 15, weight: .medium)).foregroundStyle(Scheme.primary).frame(width: 18, height: 18)
                Text(label).textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurface).lineLimit(1)
            }
            .padding(.leading, 8).padding(.trailing, 16)
            .frame(height: 32)
            .overlay(shape.strokeBorder(Scheme.outline, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle(shape: shape))
    }
}

// MARK: - attendance & grades

private struct AttendanceTab: View {
    let model: LearnModel

    var body: some View {
        LoadContent(state: model.attendance, onRetry: model.loadAll) { data in
            if let data, data.totalClasses > 0 {
                TabList {
                    SummaryCard(
                        title: "Your Attendance", subtitle: "Review your presence across all conducted sessions.",
                        figures: [
                            ("Sessions", "\(data.totalClasses)"),
                            ("Present", "\(data.presentClasses)"),
                            ("Absent", "\(data.absentClasses)"),
                            ("Rate", "\(data.percentage)%"),
                        ]
                    )
                    ForEach(data.records.sorted { $0.date > $1.date }) { r in
                        HStack {
                            Text(formatCalendarDate(r.date)).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            StatusChip(r.isPresent ? "Present" : "Absent", tone: r.isPresent ? .success : .danger)
                        }
                        .padding(14)
                        .background(Scheme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: Radius.input))
                    }
                }
            } else {
                EmptyState(title: "No attendance records found yet.")
            }
        }
    }
}

/// A website report header: a title, a line under it, and its figures (label over value).
private struct SummaryCard: View {
    let title: String
    let subtitle: String
    let figures: [(String, String)]

    var body: some View {
        AppCard {
            Text(title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
            Text(subtitle).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            Spacer().frame(height: 14)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(figures.enumerated()), id: \.offset) { i, figure in
                    if i > 0 { Spacer(minLength: 4) }
                    VStack(spacing: 0) {
                        Text(figure.1).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                        Text(figure.0.uppercased()).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct GradesTab: View {
    let model: LearnModel

    var body: some View {
        LoadContent(state: model.grades, onRetry: model.loadAll) { data in
            if let data, !data.grades.isEmpty {
                let sum = gradeSummary(data.grades)
                TabList {
                    SummaryCard(
                        title: "Grade Report", subtitle: "Detailed performance summary.",
                        figures: [
                            ("Exams", "\(sum.exams)"),
                            ("Obtained", formatMarks(sum.obtained)),
                            ("Max", formatMarks(sum.max)),
                            ("Percentage", "\(sum.percentage)%"),
                        ]
                    )
                    ForEach(data.grades.sorted { $0.date > $1.date }) { GradeRow(grade: $0) }
                }
            } else {
                EmptyState(title: "No grade records found for this student yet.")
            }
        }
    }
}

private struct GradeRow: View {
    let grade: GradeEntry

    var body: some View {
        let (marks, note) = gradeMarks(grade)
        AppCard {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(grade.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                    Text(formatCalendarDate(grade.date)).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(marks).textStyle(Typo.titleMedium)
                        .foregroundStyle(grade.marksObtained == nil ? Scheme.onSurfaceVariant : Scheme.primary)
                        .accessibilityLabel(grade.marksObtained == nil ? "Not graded" : marks)
                    if let note { Text(note).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant) }
                }
            }
        }
    }
}

// MARK: - fees

/// Whether "Pay course fee" makes sense: the student is studying the course (not finished, not waiting), it has a fee,
/// and a one-time fee isn't already paid or under review. The Pay screen's quote from the server has the final word.
func canPayCourseFee(_ enrollment: Enrollment?, _ submissions: [PaymentSubmission]) -> Bool {
    guard let enrollment, let course = enrollment.course else { return false }
    if enrollment.status != EnrollmentStatus.active || course.monthlyFeeInrPaise <= 0 { return false }
    if course.feeFrequency != "ONE_TIME" { return true }
    return !submissions.contains {
        $0.courseId == enrollment.courseId && $0.paymentType != "enrollment" && $0.status != "rejected" && $0.status != "declined"
    }
}

private struct FeesTab: View {
    let model: LearnModel
    let onPayFee: () -> Void

    var body: some View {
        LoadContent(state: model.fees, onRetry: model.loadAll) { history in
            let submissions = history.submissions.filter { $0.courseId == model.courseId }.sorted { $0.createdAt > $1.createdAt }
            TabList {
                if canPayCourseFee(model.enrollment, submissions) {
                    PrimaryButton("Pay course fee", action: onPayFee)
                    Spacer().frame(height: 8)
                }
                if submissions.isEmpty {
                    EmptyState(title: "No payments yet", message: "Payments you submit for this course are listed here.")
                }
                ForEach(submissions) { s in
                    let (label, tone) = statusLabel(s.status, kind: .payment)
                    AppCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.label).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                                Text(formatDate(s.createdAt)).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
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
        }
    }
}
