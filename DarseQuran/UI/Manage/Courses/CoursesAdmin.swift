import Observation
import SwiftUI

/*
 * The admin course pages (website: /admin/courses, /new, /[id]/edit, /[id]/students) and the course hub shared with
 * the teacher portal. Ported from Android's ui/manage/courses/CoursesAdmin.kt.
 */

// MARK: - list (/admin/courses)

struct CoursesAdminListScreen: View {
    var body: some View {
        WithModel({ app in
            PagedListModel<AdminCourseRow>(app: app) { app, page, q, _ in
                try await app.service(AdminCoursesAPI.self).list(page: page, q: q.trimmed.isEmpty ? nil : q)
            }
        }) { model in CoursesAdminListContent(model: model) }
    }
}

private struct CoursesAdminListContent: View {
    let model: PagedListModel<AdminCourseRow>
    @Environment(Navigator.self) private var nav

    var body: some View {
        ManageListScreen(
            "Courses", model: model, key: \.id, emptyTitle: "No courses yet", searchHint: "Title, category or instructor",
            fab: { AddFab("Add course") { nav.push(.manage(.courseForm())) } }
        ) { c in
            RecordCard(
                title: c.title,
                subtitle: ([c.category, c.teacherName ?? "No instructor"] + [c.duration].compactMap { $0 }.filter { !$0.trimmed.isEmpty })
                    .joined(separator: " · "),
                meta: "Registration \(rupees(c.registrationFeePaise)) · \(rupees(c.feePaise)) \(c.feeFrequencyLabel.lowercased()) · "
                    + "\(c.studentCount) student\(c.studentCount == 1 ? "" : "s")" + (c.featured ? " · Featured" : ""),
                chip: (c.statusLabel, courseStatusTone(c.status)),
                onClick: { nav.push(.manage(.courseHub(portal: .admin, courseId: c.id))) },
                leading: { RowIcon(.courses) }
            )
        }
        .reloadOnReturn { model.refresh() }
    }
}

// MARK: - course hub (course layout + its tabs)

@MainActor
final class CourseHubModel {
    let loader: Loader<CourseHeader>
    let runner: ActionRunner

    init(app: AppContainer, portal: Portal, courseId: String) {
        loader = Loader(app: app) { try await $0.service(CourseToolsAPI.self).course(portal, courseId).course }
        runner = ActionRunner(app: app)
    }
}

/// One course, as the website's course layout shows it (status, category, title, instructor), with its sections:
/// students, attendance, grade cards and announcements. Admins can also edit or delete the course here.
struct CourseHubScreen: View {
    let portal: Portal
    let courseId: String

    var body: some View {
        WithModel({ CourseHubModel(app: $0, portal: portal, courseId: courseId) }) { model in
            CourseHubContent(portal: portal, courseId: courseId, model: model)
        }
    }
}

private struct CourseHubContent: View {
    let portal: Portal
    let courseId: String
    let model: CourseHubModel
    @Environment(Navigator.self) private var nav
    @State private var confirmDelete = false

    var body: some View {
        let admin = portal == .admin
        ManageScaffold("Course", actions: {
            if admin {
                IconButton(.edit, label: "Edit course") { nav.push(.manage(.courseForm(id: courseId))) }
                IconButton(.delete, label: "Delete course") { confirmDelete = true }
            }
        }) {
            LoadedColumn(model.loader) { c in
                DetailCard {
                    HStack(alignment: .center, spacing: 8) {
                        StatusChip(c.statusLabel, tone: courseStatusTone(c.status))
                        Overline(text: c.category)
                    }
                    Text(c.title).textStyle(Typo.headlineSmall).foregroundStyle(Scheme.onSurface)
                    if admin {
                        Text(c.teacherName.map { "Instructor: \($0)" } ?? "No instructor assigned")
                            .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                    } else {
                        Text("\(c.level) · Starts \(c.startDate ?? "—")").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                    if !admin, let duration = c.duration, !duration.trimmed.isEmpty {
                        Text("Duration: \(duration)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                }
                CourseHubTile(icon: .groups, title: "Students", subtitle: admin ? "Roster, attendance and grade cards per student" : "Profiles, reports and private messages") {
                    nav.push(.manage(admin ? .courseRoster(courseId: courseId) : .teacherStudents(courseId: courseId)))
                }
                CourseHubTile(icon: .eventAvailable, title: "Attendance", subtitle: "Mark today's class and see the history") {
                    nav.push(.manage(.attendanceList(portal: portal, courseId: courseId)))
                }
                CourseHubTile(icon: .grading, title: "Grade cards", subtitle: "Test reports and marks") {
                    nav.push(.manage(.gradeList(portal: portal, courseId: courseId)))
                }
                CourseHubTile(icon: .announcement, title: "Announcements", subtitle: "Course-wide updates for enrolled students") {
                    nav.push(.manage(.courseAnnouncements(portal: portal, courseId: courseId)))
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog(
            "Delete this course?",
            message: "This cannot be undone. It is refused while students are enrolled or the course has payment, attendance, grade or coupon records; set it to Completed or On hold instead.",
            isPresented: $confirmDelete, confirm: "Delete", destructive: true
        ) {
            model.runner.run({ try await $0.service(AdminCoursesAPI.self).delete(courseId) }, success: "Course deleted.") { _ in nav.pop() }
        }
    }
}

private struct CourseHubTile: View {
    let icon: Icon
    let title: String
    let subtitle: String
    let onClick: () -> Void

    var body: some View {
        RecordCard(title: title, subtitle: subtitle, onClick: onClick, leading: { RowIcon(icon) })
    }
}

// MARK: - add / edit (/admin/courses/new, /[id]/edit)

@MainActor
@Observable
final class CourseFormModel {
    let loader: Loader<CourseFormResponse>
    let runner: ActionRunner
    var loaded = false
    var title = ""
    var description = ""
    var startDate = ""
    var duration = ""
    var categorySelect = ""
    var customCategory = ""
    var teacherId = ""
    var level = "Beginner"
    var enrollmentFee = "0"
    var fee = ""
    var frequency = "MONTHLY"
    var status = "PUBLISHED"
    var featured = false
    var confirmReopen = false

    init(app: AppContainer, id: String?) {
        loader = Loader(app: app) { app in
            let api = app.service(AdminCoursesAPI.self)
            return if let id { try await api.get(id) } else { try await api.newForm() }
        }
        runner = ActionRunner(app: app)
    }

    /// Fills the fields once, from the loaded course.
    func fillOnce() {
        guard !loaded, let form = loader.state.value else { return }
        let v = form.values
        title = v.title; description = v.description; startDate = v.startDate; duration = v.duration
        let standard = v.category.trimmed.isEmpty || form.options.categories.contains(v.category)
        categorySelect = standard ? v.category : "Other"; customCategory = standard ? "" : v.category
        teacherId = v.teacherId; level = v.level; enrollmentFee = String(v.enrollmentFeeInr); fee = String(v.monthlyFeeInr)
        frequency = v.feeFrequency; status = v.status; featured = v.featuredOnHomepage
        loaded = true
    }

    var category: String { categorySelect == "Other" ? customCategory.trimmed : categorySelect }

    func save(id: String?, onDone: @escaping () -> Void) {
        let parts = formOf { f in
            f.text("title", title.trimmed); f.text("description", description.trimmed); f.text("startDate", startDate); f.text("duration", duration.trimmed)
            f.text("category", category); f.text("teacherId", teacherId); f.text("level", level)
            f.text("enrollmentFeeInr", enrollmentFee.trimmed.isEmpty ? "0" : enrollmentFee)
            f.text("monthlyFeeInr", fee.trimmed.isEmpty ? "0" : fee)
            f.text("feeFrequency", frequency)
            f.text("status", status); f.check("featuredOnHomepage", featured && status != "DRAFT"); f.check("confirmReopen", confirmReopen)
        }
        runner.run({ app in
            let api = app.service(AdminCoursesAPI.self)
            return if let id { try await api.update(id, parts) } else { try await api.create(parts) }
        }, success: id == nil ? "Course created." : "Course updated.") { _ in onDone() }
    }
}

struct CourseFormScreen: View {
    let id: String?

    var body: some View {
        WithModel({ CourseFormModel(app: $0, id: id) }) { model in CourseFormContent(id: id, model: model) }
    }
}

private struct CourseFormContent: View {
    let id: String?
    @Bindable var model: CourseFormModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = model.loader.state
        let form = state.value
        FormScreen(
            id == nil ? "Add course" : "Edit course",
            saving: model.runner.busy,
            saveLabel: id == nil ? "Create course" : "Save changes",
            canSave: model.loaded,
            loadError: { if case .failed(let m) = state { m } else { nil } }(),
            onRetry: { model.loader.load() },
            onSave: { model.save(id: id) { nav.pop() } }
        ) {
            if let form {
                fields(form)
            } else if case .failed(let message) = state {
                Notice(message)
            } else {
                Text("Loading…").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
            }
        }
        .onChange(of: form != nil, initial: true) { _, ready in if ready { model.fillOnce() } }
    }

    @ViewBuilder private func fields(_ form: CourseFormResponse) -> some View {
        let o = form.options
        let frequencyLabel = o.feeFrequencies.first { $0.value == model.frequency }?.label
        if o.teachers.isEmpty { Notice("Add at least one teacher before creating a course.", tone: .warning) }

        FormTextField("Title", text: $model.title, isError: model.loaded && !model.title.isEmpty && model.title.trimmed.count < 3)
        FormTextField("Description", text: $model.description, singleLine: false, minLines: 4)
        FormDateField("Start date", value: model.startDate) { model.startDate = $0 }
        FormTextField("Duration", text: $model.duration, supporting: "e.g. 6 months, 1 year. Shown on course listings and detail pages.", maxLength: 80)
        FormDropdown("Category", options: withOther(o.categories).map { (value: $0, label: $0) }, value: model.categorySelect, placeholder: "Select a category") {
            model.categorySelect = $0
        }
        if model.categorySelect == "Other" { FormTextField("Specify category", text: $model.customCategory, maxLength: 100) }
        FormDropdown("Instructor", options: o.teachers.map { (value: $0.id, label: "\($0.name) — \($0.specialization)") }, value: model.teacherId, placeholder: "Select a teacher") {
            model.teacherId = $0
        }
        FormDropdown("Level", options: o.levels.map { (value: $0.value, label: $0.label) }, value: model.level, supporting: "Used for display; fees are set below per course.") {
            model.level = $0
        }

        FormSection("Fees") {
            FormNumberField("Enrollment fee (₹)", text: $model.enrollmentFee, supporting: "Use 0 when there is no one-time enrollment fee.")
            FormDropdown(
                "Fee frequency", options: o.feeFrequencies.map { (value: $0.value, label: $0.label) }, value: model.frequency,
                supporting: model.frequency == "ONE_TIME"
                    ? "Students pay once (no recurring billing)."
                    : "Students pay \((frequencyLabel ?? "monthly").lowercased()) from their profile."
            ) { model.frequency = $0 }
            FormNumberField("Fee amount (₹)", text: $model.fee, supporting: "Amount due per billing period (\((frequencyLabel ?? "Monthly").lowercased())).")
        }

        FormDropdown("Course status", options: o.statuses.map { (value: $0.value, label: "\($0.label) — \($0.description)") }, value: model.status) {
            model.status = $0
        }
        if form.values.status == "COMPLETED", model.status != "COMPLETED", id != nil {
            FormCheckbox(
                "Reopen this course anyway. Completed enrollments become active again; certificates already issued stay as they are.",
                checked: model.confirmReopen
            ) { model.confirmReopen = $0 }
        }

        FeaturedSwitch(
            featured: model.featured, currentlyFeatured: form.values.featuredOnHomepage, used: o.featuredCount, max: o.featuredMax,
            section: "Featured Courses", pageName: "Courses page", noun: "courses", condition: "when not in draft"
        ) { model.featured = $0 }
        if let id { Text("Course ID: \(id)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant) }
    }
}

// MARK: - roster (/admin/courses/[id]/students)

@MainActor
final class CourseRosterModel {
    let list: PagedListModel<RosterRow>
    let header: Loader<CourseHeader>
    let runner: ActionRunner

    init(app: AppContainer, courseId: String) {
        list = PagedListModel(app: app) { app, page, q, _ in
            try await app.service(AdminCoursesAPI.self).roster(courseId, page: page, q: q.trimmed.isEmpty ? nil : q)
        }
        header = Loader(app: app) { try await $0.service(CourseToolsAPI.self).course(.admin, courseId).course }
        runner = ActionRunner(app: app)
    }
}

struct CourseRosterScreen: View {
    let courseId: String

    var body: some View {
        WithModel({ CourseRosterModel(app: $0, courseId: courseId) }) { model in CourseRosterContent(courseId: courseId, model: model) }
    }
}

private struct CourseRosterContent: View {
    let courseId: String
    let model: CourseRosterModel
    @Environment(Navigator.self) private var nav
    @State private var removing: RosterRow?

    var body: some View {
        let course = model.header.state.value
        let completed = course?.status == "COMPLETED"
        let total = model.list.state.total
        ManageListScreen(
            "Students", model: model.list, key: \.enrollmentId,
            emptyTitle: completed ? "No completed students for this course yet" : "No active students enrolled yet",
            searchHint: "Search by name or email",
            header: {
                if let course {
                    Text("\(course.title) · \(total) \(completed ? "completed" : "active") student\(total == 1 ? "" : "s")")
                        .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        ) { s in
            RecordCard(
                title: s.name ?? s.email,
                subtitle: "Roll no \(s.rollNumberLabel)" + (s.name != nil ? " · \(s.email)" : ""),
                onClick: { nav.push(.manage(.studentAttendance(portal: .admin, courseId: courseId, enrollmentId: s.enrollmentId))) },
                leading: { RowIcon(.groups) },
                trailing: {
                    ContentRowMenu([
                        ContentRowAction("Attendance") { nav.push(.manage(.studentAttendance(portal: .admin, courseId: courseId, enrollmentId: s.enrollmentId))) },
                        ContentRowAction("Grade card") { nav.push(.manage(.studentGrades(portal: .admin, courseId: courseId, enrollmentId: s.enrollmentId))) },
                        ContentRowAction("Remove", destructive: true) { removing = s },
                    ], label: "Actions")
                }
            )
        }
        .reloadOnReturn { model.list.refresh() }
        .confirmDialog(
            item: $removing, title: "Remove enrollment",
            message: { "Remove \($0.name ?? $0.email) from this course? Their account will not be deleted; they can enroll again later." },
            confirm: "Remove", destructive: true
        ) { s in
            model.runner.run({ try await $0.service(EnrollmentsAdminAPI.self).removeEnrollment(s.enrollmentId, courseId: courseId) }, success: "Enrollment removed.") { _ in
                model.list.refresh()
            }
        }
    }
}
