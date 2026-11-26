import Observation
import SwiftUI

/*
 * Attendance (website: …/courses/[id]/attendance, /new, /[date], /[date]/edit, /student/[enrollmentId] and, for
 * admins, the attendance card PDF). Shared by the admin course pages and the teacher portal. Ported from Android's
 * ui/manage/courses/CourseAttendance.kt.
 */

// MARK: - history

@MainActor
final class AttendanceListModel {
    let loader: Loader<AttendanceListResponse>
    let runner: ActionRunner

    init(app: AppContainer, portal: Portal, courseId: String) {
        loader = Loader(app: app) { try await $0.service(CourseToolsAPI.self).attendance(portal, courseId) }
        runner = ActionRunner(app: app)
    }
}

struct AttendanceListScreen: View {
    let portal: Portal
    let courseId: String

    var body: some View {
        WithModel({ AttendanceListModel(app: $0, portal: portal, courseId: courseId) }) { model in
            AttendanceListContent(portal: portal, courseId: courseId, model: model)
        }
    }
}

private struct AttendanceListContent: View {
    let portal: Portal
    let courseId: String
    let model: AttendanceListModel
    @Environment(Navigator.self) private var nav
    @State private var deleting: AttendanceDay?

    var body: some View {
        let take = { nav.push(.manage(.attendanceTake(portal: portal, courseId: courseId, date: nil))) }
        ManageScaffold("Attendance", fab: { AddFab("Mark attendance", icon: .eventAvailable, action: take) }) {
            LoadedColumn(model.loader) { list in
                if let c = list.course {
                    Text(c.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.primary)
                }
                if list.data.isEmpty {
                    EmptyState(title: "No attendance yet", message: "No attendance records found for this course.", action: "Mark attendance", onAction: take)
                }
                ForEach(list.data) { d in
                    RecordCard(
                        title: d.dateLabel,
                        subtitle: "\(d.present) present · \(d.absent) absent",
                        meta: "\(d.total) enrolled",
                        onClick: { nav.push(.manage(.attendanceDay(portal: portal, courseId: courseId, date: d.date))) },
                        leading: { RowIcon(.eventAvailable) },
                        trailing: { IconButton(.delete, label: "Delete", tint: Scheme.error) { deleting = d } }
                    )
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog(
            item: $deleting, title: "Delete attendance?",
            message: { "Attendance for \($0.dateLabel) will be deleted for every student. This cannot be undone." },
            confirm: "Delete", destructive: true
        ) { d in
            model.runner.run({ try await $0.service(CourseToolsAPI.self).deleteAttendance(portal, courseId, date: d.date) }, success: "Attendance deleted.") { _ in
                model.loader.reload()
            }
        }
    }
}

// MARK: - mark / edit (one tap per student)

/// The state of a day's attendance form: the class list, the saved day (when editing one), the marks and the day.
@MainActor
@Observable
final class AttendanceTakeModel {
    let portal: Portal
    let courseId: String
    let date: String?
    let students: Loader<[GradableStudent]>
    let saved: Loader<AttendanceDayDetail>?
    let runner: ActionRunner
    let entries = RosterEntries<Bool>()
    var day: String
    /// A new day that turns out to be marked already: saving would replace it for every student.
    var alreadyMarked: String?
    @ObservationIgnored private let app: AppContainer

    init(app: AppContainer, portal: Portal, courseId: String, date: String?) {
        self.app = app
        self.portal = portal
        self.courseId = courseId
        self.date = date
        day = date ?? academyTodayIso()
        students = Loader(app: app) { try await $0.service(CourseToolsAPI.self).attendanceStudents(portal, courseId).data }
        saved = date.map { d in Loader(app: app) { try await $0.service(CourseToolsAPI.self).attendanceDay(portal, courseId, date: d) } }
        runner = ActionRunner(app: app)
    }

    var roster: [GradableStudent]? { students.state.value }
    var savedDay: AttendanceDayDetail? { saved?.state.value }

    /// Everything the form needs has loaded.
    var ready: Bool { roster != nil && (date == nil || savedDay != nil) }

    /// Fills the marks once: everyone present, or as saved when editing a day.
    func initialise() {
        guard let roster, ready else { return }
        let previous = Dictionary((savedDay?.records ?? []).map { ($0.enrollmentId, $0.isPresent ?? true) }) { a, _ in a }
        entries.initialiseOnce { Dictionary(roster.map { ($0.enrollmentId, previous[$0.enrollmentId] ?? true) }) { a, _ in a } }
    }

    func isPresent(_ enrollmentId: String) -> Bool { entries.values[enrollmentId] ?? true }
    func toggle(_ enrollmentId: String) { entries.values[enrollmentId] = !isPresent(enrollmentId) }
    func setAll(_ present: Bool) { roster?.forEach { entries.values[$0.enrollmentId] = present } }
    var presentCount: Int { roster?.filter { isPresent($0.enrollmentId) }.count ?? 0 }

    var loadError: String? {
        if case .failed(let m) = students.state { return m }
        if case .failed(let m)? = saved?.state { return m }
        return nil
    }

    func retry() { students.load(); saved?.load() }

    /// Save: a new day is checked first, so a day that is already marked isn't replaced by mistake.
    func save(onDone: @escaping () -> Void) {
        if day.trimmed.isEmpty { runner.message("Please select a date."); return }
        if date != nil { store(onDone: onDone); return } // editing that day on purpose
        let (portal, courseId, day) = (portal, courseId, day)
        runner.run({ try await $0.service(CourseToolsAPI.self).isMarked(portal, courseId, date: day) }) { [weak self] marked in
            if marked { self?.alreadyMarked = day } else { self?.store(onDone: onDone) }
        }
    }

    /// "Open that day" in the already-marked dialog: the day to edit instead.
    func openMarkedDay() -> String? {
        let d = alreadyMarked
        alreadyMarked = nil
        return d
    }

    private func store(onDone: @escaping () -> Void) {
        let body = AttendanceSave(records: (roster ?? []).map { AttendanceMark(enrollmentId: $0.enrollmentId, isPresent: isPresent($0.enrollmentId)) })
        let (portal, courseId, day) = (portal, courseId, day)
        runner.run({ try await $0.service(CourseToolsAPI.self).saveAttendance(portal, courseId, date: day, body) }, success: "Attendance saved.") { _ in onDone() }
    }
}

extension CourseToolsAPI {
    /// Whether [date] already has attendance (the website answers 404 for a day with none).
    func isMarked(_ portal: Portal, _ courseId: String, date: String) async throws -> Bool {
        do {
            return try await attendanceDay(portal, courseId, date: date).records.contains { $0.isPresent != nil }
        } catch let e as HTTPError where e.status == 404 {
            return false
        }
    }
}

/// Marks a day's attendance: everyone starts present (or as saved, when editing [date]); tap a student to flip them,
/// "All present" / "All absent" for the whole class, then Save.
struct AttendanceTakeScreen: View {
    let portal: Portal
    let courseId: String
    let date: String?

    var body: some View {
        WithModel({ AttendanceTakeModel(app: $0, portal: portal, courseId: courseId, date: date) }) { model in
            AttendanceTakeContent(model: model)
        }
    }
}

private struct AttendanceTakeContent: View {
    let model: AttendanceTakeModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let roster = model.roster
        ManageScaffold(model.date == nil ? "Mark attendance" : "Edit attendance", bottomBar: {
            if let roster, !roster.isEmpty {
                PrimaryButton("Save attendance (\(model.presentCount) of \(roster.count) present)", loading: model.runner.busy) {
                    model.save { nav.pop() }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Scheme.surfaceContainer.ignoresSafeArea(edges: .bottom))
            }
        }) {
            if let failed = model.loadError {
                ErrorState(message: failed) { model.retry() }
            } else if let roster, model.entries.initialised {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if model.date == nil {
                            FormDateField("Date", value: model.day) { model.day = $0 }
                        } else {
                            Text("Date: \(model.savedDay?.dateLabel ?? model.date ?? "")").textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                        }
                        if roster.isEmpty {
                            EmptyState(title: "No active students", message: "No active students enrolled in this course yet.")
                        } else {
                            HStack(spacing: 8) {
                                ContentOutlinedButton("All present", fullWidth: true) { model.setAll(true) }
                                ContentOutlinedButton("All absent", fullWidth: true) { model.setAll(false) }
                            }
                            Text("Tap a student to switch between present and absent.").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                            ForEach(roster) { s in
                                AttendanceToggleRow(student: s, present: model.isPresent(s.enrollmentId)) { model.toggle(s.enrollmentId) }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
                }
            } else {
                LoadingBox()
            }
        }
        .onChange(of: model.ready, initial: true) { _, ready in if ready { model.initialise() } }
        .confirmDialog(
            item: Binding(get: { model.alreadyMarked }, set: { model.alreadyMarked = $0 }), title: "Attendance already marked",
            message: { "Attendance for \(formatDate($0)) is already saved. Saving here would replace it for every student. Open that day to change it instead." },
            confirm: "Open that day"
        ) { _ in
            guard let d = model.openMarkedDay() else { return }
            nav.replace(
                upTo: .manage(.attendanceTake(portal: model.portal, courseId: model.courseId, date: nil)),
                with: .manage(.attendanceTake(portal: model.portal, courseId: model.courseId, date: d))
            )
        }
    }
}

/// One student, tinted green when present and red when absent; a tap flips them.
private struct AttendanceToggleRow: View {
    let student: GradableStudent
    let present: Bool
    let onToggle: () -> Void

    var body: some View {
        let s = student
        let bg = present ? Brand.successContainer : Brand.dangerContainer
        let fg = present ? Brand.success : Brand.danger
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 0) {
                Text(s.rollNumberLabel).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurfaceVariant).frame(minWidth: 32, alignment: .leading)
                Spacer().frame(width: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.name ?? s.email).textStyle(Typo.bodyLarge.with(name: FontName.sansMedium)).foregroundStyle(Scheme.onSurface).lineLimit(1)
                    if s.name != nil {
                        Text(s.email).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 10)
                HStack(spacing: 4) {
                    (present ? Icon.check : Icon.close).image.font(.system(size: 14, weight: .bold)).foregroundStyle(fg).frame(width: 18, height: 18)
                    Text(present ? "Present" : "Absent").textStyle(Typo.labelLarge).foregroundStyle(fg)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(bg, in: Capsule())
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(bg.opacity(0.45), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle(shape: shape))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double-tap to switch between present and absent")
    }
}

// MARK: - one day

@MainActor
final class AttendanceDayModel {
    let loader: Loader<AttendanceDayDetail>
    let runner: ActionRunner

    init(app: AppContainer, portal: Portal, courseId: String, date: String) {
        loader = Loader(app: app) { try await $0.service(CourseToolsAPI.self).attendanceDay(portal, courseId, date: date) }
        runner = ActionRunner(app: app)
    }
}

struct AttendanceDayScreen: View {
    let portal: Portal
    let courseId: String
    let date: String

    var body: some View {
        WithModel({ AttendanceDayModel(app: $0, portal: portal, courseId: courseId, date: date) }) { model in
            AttendanceDayContent(portal: portal, courseId: courseId, date: date, model: model)
        }
    }
}

private struct AttendanceDayContent: View {
    let portal: Portal
    let courseId: String
    let date: String
    let model: AttendanceDayModel
    @Environment(Navigator.self) private var nav
    @State private var confirmDelete = false

    var body: some View {
        ManageScaffold("Attendance record", actions: {
            IconButton(.edit, label: "Edit records") { nav.push(.manage(.attendanceTake(portal: portal, courseId: courseId, date: date))) }
            IconButton(.delete, label: "Delete") { confirmDelete = true }
        }) {
            LoadedColumn(model.loader) { d in
                DetailCard(d.dateLabel) {
                    Text("Summary: \(d.present) Present, \(d.absent) Absent (\(d.total) Total Enrolled)").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                }
                if d.records.isEmpty {
                    EmptyState(title: "No records", message: "No attendance records logged for this session.")
                }
                ForEach(d.records) { r in
                    RecordCard(
                        title: r.name ?? "Student",
                        subtitle: "Roll no \(r.rollNumberLabel) · \(r.email)",
                        onClick: { nav.push(.manage(.studentAttendance(portal: portal, courseId: courseId, enrollmentId: r.enrollmentId))) },
                        trailing: { CoursePresenceChip(present: r.isPresent == true) }
                    )
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog(
            "Delete attendance?", message: "Attendance for this day will be deleted for every student. This cannot be undone.",
            isPresented: $confirmDelete, confirm: "Delete", destructive: true
        ) {
            model.runner.run({ try await $0.service(CourseToolsAPI.self).deleteAttendance(portal, courseId, date: date) }, success: "Attendance deleted.") { _ in
                nav.pop()
            }
        }
    }
}

/// "Present" (green) or "Absent" (red).
struct CoursePresenceChip: View {
    let present: Bool
    var body: some View { StatusChip(present ? "Present" : "Absent", tone: present ? .success : .danger) }
}

// MARK: - one student

@MainActor
final class StudentAttendanceModel {
    let loader: Loader<AttendanceReport>
    let runner: ActionRunner

    init(app: AppContainer, portal: Portal, courseId: String, enrollmentId: String) {
        loader = Loader(app: app) { try await $0.service(CourseToolsAPI.self).attendanceReport(portal, courseId, enrollmentId: enrollmentId) }
        runner = ActionRunner(app: app)
    }
}

struct StudentAttendanceScreen: View {
    let portal: Portal
    let courseId: String
    let enrollmentId: String

    var body: some View {
        WithModel({ StudentAttendanceModel(app: $0, portal: portal, courseId: courseId, enrollmentId: enrollmentId) }) { model in
            StudentAttendanceContent(courseId: courseId, enrollmentId: enrollmentId, model: model)
        }
    }
}

private struct StudentAttendanceContent: View {
    let courseId: String
    let enrollmentId: String
    let model: StudentAttendanceModel

    var body: some View {
        ManageScaffold("Attendance report") {
            LoadedColumn(model.loader) { r in
                CourseReportHeader(student: r.student, courseTitle: r.courseTitle)
                HStack(spacing: 10) {
                    StatTile("Sessions", "\(r.summary.total)").frame(maxWidth: .infinity)
                    StatTile("Present", "\(r.summary.present)").frame(maxWidth: .infinity)
                    StatTile("Absent", "\(r.summary.absent)").frame(maxWidth: .infinity)
                    StatTile("Rate", "\(r.summary.percentage)%", highlight: r.summary.total > 0 && r.summary.percentage < 75).frame(maxWidth: .infinity)
                }
                if r.canDownloadCard {
                    CourseStudentCardActions(runner: model.runner, courseId: courseId, enrollmentId: enrollmentId, kind: "attendance", label: "Attendance card", student: r.student)
                }
                if r.records.isEmpty {
                    EmptyState(title: "No attendance yet", message: "No attendance records found for this student yet.")
                } else {
                    AppCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(r.records.enumerated()), id: \.element.id) { i, rec in
                                if i > 0 { ManageDivider() }
                                HStack(alignment: .center) {
                                    Text(rec.dateLabel).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                                    CoursePresenceChip(present: rec.isPresent)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
    }
}

/// The student and course a report is for.
struct CourseReportHeader: View {
    let student: ReportStudent
    let courseTitle: String

    var body: some View {
        DetailCard {
            Text(student.name ?? "Student").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
            Text("\(student.email) · Roll no \(student.rollNumberLabel)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            Text(courseTitle).textStyle(Typo.titleSmall).foregroundStyle(Scheme.primary)
        }
    }
}

/// Admins: open the card PDF or e-mail it to the student (website: …/attendance-card, …/grade-card).
struct CourseStudentCardActions: View {
    let runner: ActionRunner
    let courseId: String
    let enrollmentId: String
    let kind: String
    let label: String
    let student: ReportStudent

    var body: some View {
        let (courseId, enrollmentId, kind, label) = (courseId, enrollmentId, kind, label)
        DetailCard(label) {
            Text("Official record issued by the academy, as a PDF.").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            HStack(spacing: 8) {
                PillOutlinedButton("View", icon: .badge, enabled: !runner.busy) {
                    let fileName = "\(label.replacingOccurrences(of: " ", with: "_"))_\((student.name ?? "Student").replacingOccurrences(of: " ", with: "_")).pdf"
                    runner.openFile { try await $0.service(AdminCoursesAPI.self).card(courseId, kind: kind, enrollmentId: enrollmentId, fileName: fileName) }
                }
                PillOutlinedButton("Send via email", icon: .mail, enabled: !runner.busy) {
                    runner.run(
                        { try await $0.service(AdminCoursesAPI.self).emailCard(courseId, kind: kind, enrollmentId: enrollmentId) },
                        success: "\(label) sent. Ask the student to check their Inbox or Spam/Junk folder."
                    )
                }
            }
        }
    }
}
