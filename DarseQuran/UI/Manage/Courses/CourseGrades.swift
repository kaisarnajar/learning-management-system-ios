import Foundation
import Observation
import SwiftUI

/*
 * Grade cards / test reports (website: …/courses/[id]/grades, /new, /[gradeId]/edit, /student/[enrollmentId] and,
 * for admins, the grade card PDF). Shared by the admin course pages and the teacher portal. Ported from Android's
 * ui/manage/courses/CourseGrades.kt.
 */

/// Android's formatMarks (renamed: the student app has its own). Marks with at most two decimals, without trailing zeros (as the website shows them). Always ASCII digits and a
/// "." whatever the phone's language: the text goes back into the marks field, which parses it with Double().
func formatCourseMarks(_ marks: Double) -> String {
    guard marks.isFinite, var value = Decimal(string: String(marks), locale: Locale(identifier: "en_US_POSIX")) else { return String(marks) }
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 2, .plain)
    let text = rounded.description
    return text == "-0" ? "0" : text
}

// MARK: - list

@MainActor
final class GradeListModel {
    let loader: Loader<GradeListResponse>
    let runner: ActionRunner

    init(app: AppContainer, portal: Portal, courseId: String) {
        loader = Loader(app: app) { try await $0.service(CourseToolsAPI.self).grades(portal, courseId) }
        runner = ActionRunner(app: app)
    }
}

struct GradeListScreen: View {
    let portal: Portal
    let courseId: String

    var body: some View {
        WithModel({ GradeListModel(app: $0, portal: portal, courseId: courseId) }) { model in
            GradeListContent(portal: portal, courseId: courseId, model: model)
        }
    }
}

private struct GradeListContent: View {
    let portal: Portal
    let courseId: String
    let model: GradeListModel
    @Environment(Navigator.self) private var nav
    @State private var deleting: GradeCardRow?

    var body: some View {
        let add = { nav.push(.manage(.gradeForm(portal: portal, courseId: courseId, gradeId: nil))) }
        ManageScaffold("Grade cards", fab: { AddFab("Add test report", action: add) }) {
            LoadedColumn(model.loader) { list in
                if let c = list.course {
                    Text(c.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.primary)
                }
                if list.data.isEmpty {
                    EmptyState(title: "No grade cards yet", message: "No grade cards found for this course.", action: "Add test report", onAction: add)
                }
                ForEach(list.data) { g in
                    RecordCard(
                        title: g.title,
                        subtitle: "\(g.dateLabel) · Max marks \(g.maxMarks)",
                        meta: "\(g.graded) student\(g.graded == 1 ? "" : "s") graded",
                        onClick: { nav.push(.manage(.gradeForm(portal: portal, courseId: courseId, gradeId: g.id))) },
                        leading: { RowIcon(.grading) },
                        trailing: { IconButton(.delete, label: "Delete", tint: Scheme.error) { deleting = g } }
                    )
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog(
            item: $deleting, title: "Delete grade card?",
            message: { "Grade Card \"\($0.title)\" and every student's marks in it will be deleted. This cannot be undone." },
            confirm: "Delete", destructive: true
        ) { g in
            model.runner.run({ try await $0.service(CourseToolsAPI.self).deleteGrade(portal, courseId, gradeId: g.id) }, success: "Grade card deleted.") { _ in
                model.loader.reload()
            }
        }
    }
}

// MARK: - add / edit

/// A new test report or an edit of one: title, date, maximum marks and each active student's marks (blank = not graded).
@MainActor
@Observable
final class GradeFormModel {
    let portal: Portal
    let courseId: String
    let gradeId: String?
    let students: Loader<[GradableStudent]>
    let existing: Loader<GradeDetail>?
    let runner: ActionRunner
    let entries = RosterEntries<String>()
    var title = ""
    var date = academyTodayIso()
    var maxMarks = ""

    init(app: AppContainer, portal: Portal, courseId: String, gradeId: String?) {
        self.portal = portal
        self.courseId = courseId
        self.gradeId = gradeId
        students = Loader(app: app) { try await $0.service(CourseToolsAPI.self).gradeStudents(portal, courseId).data }
        existing = gradeId.map { g in Loader(app: app) { try await $0.service(CourseToolsAPI.self).grade(portal, courseId, gradeId: g).grade } }
        runner = ActionRunner(app: app)
    }

    var roster: [GradableStudent]? { students.state.value }
    var grade: GradeDetail? { existing?.state.value }
    var ready: Bool { roster != nil && (gradeId == nil || grade != nil) }

    var loadError: String? {
        if case .failed(let m) = students.state { return m }
        if case .failed(let m)? = existing?.state { return m }
        return nil
    }

    func retry() { students.load(); existing?.load() }

    func initialise() {
        guard !entries.initialised, ready, let roster else { return }
        if let grade { title = grade.title; date = grade.date; maxMarks = String(grade.maxMarks) }
        var previous: [String: Double] = [:]
        for r in grade?.records ?? [] { previous[r.enrollmentId] = r.marksObtained }
        entries.initialiseOnce { Dictionary(roster.map { s in (s.enrollmentId, previous[s.enrollmentId].map(formatCourseMarks) ?? "") }) { a, _ in a } }
    }

    func marks(_ enrollmentId: String) -> String { entries.values[enrollmentId] ?? "" }

    /// Keeps digits and one dot with at most two decimals; anything else is refused.
    func setMarks(_ enrollmentId: String, _ value: String) {
        let clean = value.filter { ($0.isNumber && $0.isASCII) || $0 == "." }
        let decimals = clean.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
        if clean.filter({ $0 == "." }).count <= 1 && decimals <= 2 { entries.values[enrollmentId] = clean }
    }

    var max: Int? { Int(maxMarks) }

    func validate() -> String? {
        if date.trimmed.isEmpty { return "Please select a date." }
        if title.trimmed.isEmpty { return "Please provide an exam title." }
        guard let max, max > 0 else { return "Maximum marks must be a whole number greater than 0." }
        let values = (roster ?? []).compactMap { s -> String? in
            let v = marks(s.enrollmentId)
            return v.trimmed.isEmpty ? nil : v
        }
        if values.contains(where: { Double($0) == nil }) { return "Marks must be numbers." }
        if values.contains(where: { Double($0)! < 0 || Double($0)! > Double(max) }) { return "Marks must be between 0 and \(max)." }
        return nil
    }

    /// Whether a typed mark is out of range or unreadable.
    func isBad(_ value: String) -> Bool {
        guard !value.trimmed.isEmpty else { return false }
        guard let v = Double(value) else { return true }
        return v < 0 || (max.map { v > Double($0) } ?? false)
    }

    func save(onDone: @escaping () -> Void) {
        if let problem = validate() { runner.message(problem); return }
        guard let roster, !roster.isEmpty, let max else { runner.message("No active students enrolled in this course yet."); return }
        let body = GradeSave(
            title: title.trimmed, date: date, maxMarks: max,
            records: roster.map { s in
                let v = marks(s.enrollmentId)
                return GradeMark(enrollmentId: s.enrollmentId, marksObtained: v.trimmed.isEmpty ? nil : Double(v))
            }
        )
        let (portal, courseId, gradeId) = (portal, courseId, gradeId)
        runner.run({ app in
            let api = app.service(CourseToolsAPI.self)
            return if let gradeId { try await api.updateGrade(portal, courseId, gradeId: gradeId, body) } else { try await api.createGrade(portal, courseId, body) }
        }, success: "Grades saved.") { _ in onDone() }
    }
}

struct GradeFormScreen: View {
    let portal: Portal
    let courseId: String
    let gradeId: String?

    var body: some View {
        WithModel({ GradeFormModel(app: $0, portal: portal, courseId: courseId, gradeId: gradeId) }) { model in GradeFormContent(model: model) }
    }
}

private struct GradeFormContent: View {
    @Bindable var model: GradeFormModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let failed = model.loadError
        FormScreen(
            model.gradeId == nil ? "Add test report" : "Edit grade card",
            saving: model.runner.busy,
            saveLabel: "Save grades",
            canSave: model.roster != nil && model.entries.initialised,
            loadError: failed,
            onRetry: { model.retry() },
            onSave: { model.save { nav.pop() } }
        ) {
            if let roster = model.roster, model.entries.initialised {
                Text(model.gradeId == nil ? "Record exam performance for enrolled students." : "Update exam performance for enrolled students.")
                    .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                FormTextField("Exam title", text: $model.title, supporting: "e.g. Mid-Term", maxLength: 200)
                FormDateField("Date", value: model.date) { model.date = $0 }
                FormNumberField("Max marks", text: $model.maxMarks)
                if roster.isEmpty {
                    Notice("No active students enrolled in this course yet.", tone: .info)
                } else {
                    Text("Marks obtained (leave blank when not graded)").textStyle(Typo.titleSmall).foregroundStyle(Scheme.primary)
                    AppCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(roster.enumerated()), id: \.element.id) { i, s in
                                if i > 0 { ManageDivider() }
                                HStack(alignment: .center, spacing: 0) {
                                    Text(s.rollNumberLabel).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurfaceVariant).frame(minWidth: 30, alignment: .leading)
                                    Spacer().frame(width: 8)
                                    Text(s.name ?? s.email).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    let value = model.marks(s.enrollmentId)
                                    CourseMarksField(
                                        name: s.name ?? s.email,
                                        text: Binding(get: { model.marks(s.enrollmentId) }, set: { model.setMarks(s.enrollmentId, $0) }),
                                        max: model.max, isError: model.isBad(value)
                                    )
                                }
                                .padding(.horizontal, 14).padding(.vertical, 6)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if failed == nil {
                Text("Loading…").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
            }
        }
        .onChange(of: model.ready, initial: true) { _, ready in if ready { model.initialise() } }
    }
}

/// One student's marks: a 120pt outlined field with "—" as placeholder and "/max" after the number.
private struct CourseMarksField: View {
    let name: String
    @Binding var text: String
    let max: Int?
    let isError: Bool
    @FocusState private var focused: Bool
    @State private var shown: String? = nil

    var body: some View {
        let outline = isError ? Scheme.error : (focused ? Scheme.primary : Scheme.outline)
        HStack(spacing: 2) {
            // A third decimal or a letter is refused (setMarks), and the field shows what is kept.
            TextField("", text: $text.shown($shown), prompt: Text("—").foregroundStyle(Scheme.onSurfaceVariant))
                .correctsRefusedEdits(text: text, shown: $shown)
                .textStyle(Typo.bodyLarge)
                .foregroundStyle(Scheme.onSurface)
                .keyboardType(.decimalPad)
                .focused($focused)
                .tint(Scheme.primary)
            if let max { Text("/\(max)").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurfaceVariant) }
        }
        .padding(.horizontal, 16)
        .frame(width: 120, height: 56)
        .overlay(RoundedRectangle(cornerRadius: Radius.xs).strokeBorder(outline, lineWidth: focused || isError ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .accessibilityLabel("Marks for \(name)")
    }
}

// MARK: - one student

@MainActor
final class StudentGradesModel {
    let loader: Loader<GradeReport>
    let runner: ActionRunner

    init(app: AppContainer, portal: Portal, courseId: String, enrollmentId: String) {
        loader = Loader(app: app) { try await $0.service(CourseToolsAPI.self).gradeReport(portal, courseId, enrollmentId: enrollmentId) }
        runner = ActionRunner(app: app)
    }
}

struct StudentGradesScreen: View {
    let portal: Portal
    let courseId: String
    let enrollmentId: String

    var body: some View {
        WithModel({ StudentGradesModel(app: $0, portal: portal, courseId: courseId, enrollmentId: enrollmentId) }) { model in
            StudentGradesContent(courseId: courseId, enrollmentId: enrollmentId, model: model)
        }
    }
}

private struct StudentGradesContent: View {
    let courseId: String
    let enrollmentId: String
    let model: StudentGradesModel

    var body: some View {
        ManageScaffold("Grade report") {
            LoadedColumn(model.loader) { r in
                CourseReportHeader(student: r.student, courseTitle: r.courseTitle)
                HStack(spacing: 10) {
                    StatTile("Exams", "\(r.summary.exams)").frame(maxWidth: .infinity)
                    StatTile("Obtained", formatCourseMarks(r.summary.obtained)).frame(maxWidth: .infinity)
                    StatTile("Max", "\(r.summary.max)").frame(maxWidth: .infinity)
                    StatTile("Percentage", "\(r.summary.percentage)%", highlight: r.summary.max > 0 && r.summary.percentage < 40).frame(maxWidth: .infinity)
                }
                if r.canDownloadCard {
                    CourseStudentCardActions(runner: model.runner, courseId: courseId, enrollmentId: enrollmentId, kind: "grades", label: "Grade card", student: r.student)
                }
                if r.records.isEmpty {
                    EmptyState(title: "No grades yet", message: "No grade records found for this student yet.")
                } else {
                    AppCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(r.records.enumerated()), id: \.element.id) { i, rec in
                                if i > 0 { ManageDivider() }
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(rec.title).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                                        Text(rec.dateLabel).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(formatCourseMarks(rec.marksObtained)) / \(rec.maxMarks)").textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
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
