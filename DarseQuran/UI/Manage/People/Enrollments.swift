import Observation
import SwiftUI

/*
 * Enrollments: /admin/enrollments (free requests and paid enrollments awaiting the fee) and "enrol a student".
 * Ported from Android's ui/manage/people/Enrollments.kt.
 */

private let enrollmentsPaid = "paid_awaiting"

private enum EnrollmentAsk: Identifiable {
    case approve(EnrollmentRequest)
    case reject(EnrollmentRequest)

    var e: EnrollmentRequest { switch self { case .approve(let e), .reject(let e): e } }
    var id: String { switch self { case .approve(let e): "approve-\(e.id)"; case .reject(let e): "reject-\(e.id)" } }
}

/// " (n)" after a tab's name when there are any.
private func enrollmentsCount(_ n: Int?) -> String { if let n, n > 0 { " (\(n))" } else { "" } }

@MainActor
@Observable
final class EnrollmentsModel {
    let list: PagedListModel<EnrollmentRequest>
    let summary: Loader<EnrollmentsSummary>
    let runner: ActionRunner
    fileprivate var asking: EnrollmentAsk?

    init(app: AppContainer) {
        list = PagedListModel(app: app) { app, page, q, type in
            try await app.service(EnrollmentsAdminAPI.self).list(page: page, q: q.trimmed.isEmpty ? nil : q, type: type)
        }
        summary = Loader(app: app) { try await $0.service(EnrollmentsAdminAPI.self).summary() }
        runner = ActionRunner(app: app)
    }

    func reload() { list.refresh(); summary.reload() }
}

/// /admin/enrollments: free-course requests to approve or reject, paid enrollments awaiting the fee (reject only;
/// the fee is verified under Payments), and "enrol a student" (the floating button).
struct EnrollmentsScreen: View {
    var body: some View {
        WithModel({ EnrollmentsModel(app: $0) }) { model in EnrollmentsContent(model: model) }
    }
}

private struct EnrollmentsContent: View {
    @Bindable var model: EnrollmentsModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let counts = model.summary.state.value
        let paid = model.list.state.filter == enrollmentsPaid
        let busy = model.runner.busy
        ManageListScreen(
            "Course enrollments", model: model.list, key: \.id,
            emptyTitle: paid ? "No paid enrollments awaiting student payment" : "No free enrollment requests awaiting approval",
            searchHint: "Student name, e-mail or course",
            filters: [
                FilterOption(nil, "Free requests" + enrollmentsCount(counts?.freeCount)),
                FilterOption(enrollmentsPaid, "Paid, awaiting fee" + enrollmentsCount(counts?.paidCount)),
            ],
            fab: { AddFab("Enrol a student") { nav.push(.manage(.enrollStudent)) } },
            header: {
                Text(
                    paid
                        ? "Students must pay the enrollment fee first. Once they submit payment, verify it under enrollment fee approvals — approving payment activates the enrollment automatically."
                        : "Courses with no enrollment fee. Approve to grant access immediately."
                )
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                if paid, let payments = routeForAdminHref("/admin/payments") {
                    HStack {
                        PillOutlinedButton("Go to enrollment fee approvals") { nav.push(.manage(payments)) }
                        Spacer()
                    }
                }
            }
        ) { e in
            PeopleActionCard(
                title: e.user.name ?? e.user.email,
                subtitle: [e.user.name != nil ? e.user.email : nil, e.courseTitle].compactMap { $0 }.joined(separator: " · "),
                meta: "Requested " + formatDate(e.createdAt)
            ) {
                if !paid { PeopleSmallPrimary("Approve", enabled: !busy) { model.asking = .approve(e) } }
                PeopleSmallDanger("Reject", enabled: !busy) { model.asking = .reject(e) }
                if let uid = e.user.id { PeopleSmallOutlined("Student profile") { nav.push(.manage(.studentAdmin(id: uid))) } }
            }
        }
        .reloadOnReturn { model.reload() }
        .alert(askTitle, isPresented: Binding(get: { model.asking != nil }, set: { if !$0 { model.asking = nil } }), presenting: model.asking) { ask in
            Button("Cancel", role: .cancel) {}
            switch ask {
            case .approve(let e):
                Button("Approve") {
                    model.runner.run(
                        { try await $0.service(EnrollmentsAdminAPI.self).approve(e.id, formOf { $0.text("courseId", e.courseId) }) },
                        success: "Enrollment approved. The student will be notified."
                    ) { _ in model.reload() }
                }
            case .reject(let e):
                Button("Reject", role: .destructive) {
                    model.runner.run(
                        { try await $0.service(EnrollmentsAdminAPI.self).reject(e.id, formOf { $0.text("courseId", e.courseId) }) },
                        success: "Enrollment rejected. The student will be notified."
                    ) { _ in model.reload() }
                }
            }
        } message: { ask in
            switch ask {
            case .approve: Text("Approve this student enrollment and notify them?")
            case .reject: Text("Reject this enrollment request?")
            }
        }
    }

    private var askTitle: String {
        switch model.asking {
        case .approve: "Approve enrollment"
        case .reject: "Reject enrollment"
        case nil: ""
        }
    }
}

// MARK: - enrol a student

@MainActor
@Observable
final class EnrollStudentModel {
    let runner: ActionRunner
    let summary: Loader<EnrollmentsSummary>
    let account: AccountCheck
    var courseId = ""
    var error: String?
    var done: String?

    init(app: AppContainer) {
        runner = ActionRunner(app: app)
        summary = Loader(app: app) { try await $0.service(EnrollmentsAdminAPI.self).summary() }
        account = AccountCheck(app: app) { app, email in
            AccountAnswer(try await app.service(EnrollmentsAdminAPI.self).lookup(email: email).lookup)
        }
    }

    func save() {
        error = if account.email.trimmed.isEmpty { "Enter the student's e-mail." }
            else if let e = account.error { e }
            else if !account.verified { "Check the account e-mail first." }
            else if courseId.trimmed.isEmpty { "Select a course." }
            else { nil }
        guard error == nil else { return }
        let email = account.email.trimmed
        let courseId = courseId
        runner.run({ try await $0.service(EnrollmentsAdminAPI.self).enroll(formOf { f in f.text("email", email); f.text("courseId", courseId) }) }) { [weak self] r in
            guard let self else { return }
            self.done = r.stringResult("success") ?? "Enrollment added."
            self.account.reset()
            self.courseId = ""
            self.summary.reload()
        }
    }
}

/// "Enroll a student manually": a registered account's e-mail and an open course; enrols with full access.
struct EnrollStudentScreen: View {
    var body: some View {
        WithModel({ EnrollStudentModel(app: $0) }) { model in EnrollStudentContent(model: model) }
    }
}

private struct EnrollStudentContent: View {
    @Bindable var model: EnrollStudentModel

    var body: some View {
        let courses = model.summary.state.value?.enrollableCourses ?? []
        let account = model.account
        FormScreen("Enrol a student", saving: model.runner.busy, saveLabel: "Add enrollment", error: model.error, onSave: { model.save() }) {
            Text("The student must already have registered. Enter their e-mail and choose a course to enrol them directly with full access.")
                .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
            Notice(model.done, tone: .success)
            FormTextField(
                "Registered account email",
                text: Binding(get: { account.email }, set: { account.edit($0); model.done = nil }),
                keyboard: .email
            )
            PillOutlinedButton(account.checking ? "Checking…" : "Check account", enabled: !account.checking && !account.email.trimmed.isEmpty) {
                account.verify()
            }
            Notice(account.error, tone: .warning)
            Field(
                "Name (from account)",
                account.checking ? "Checking account…" : (account.name.trimmed.isEmpty ? "Check the e-mail above to load the account name." : account.name)
            )
            FormDropdown("Course", options: courses.map { (value: $0.id, label: $0.title) }, value: model.courseId, placeholder: "Select a course") {
                model.courseId = $0
            }
        }
    }
}
