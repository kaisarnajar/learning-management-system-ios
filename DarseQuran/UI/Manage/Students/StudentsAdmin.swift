import Observation
import SwiftUI

/*
 * Students: /admin/students (list), /admin/students/[id] (profile, enrollments, payments) and the edit form.
 * Ported from Android's ui/manage/students/StudentsAdmin.kt.
 */

private let studentsSorts = [
    FilterOption(nil, "Reg. no"),
    FilterOption("name_asc", "Name A–Z"),
    FilterOption("date_desc", "Newest"),
    FilterOption("date_asc", "Oldest"),
    FilterOption("email_asc", "E-mail"),
]

// MARK: - list

struct StudentsListScreen: View {
    var body: some View {
        WithModel({ app in
            PagedListModel<StudentRow>(app: app) { app, page, q, sort in
                try await app.service(StudentsAdminAPI.self).list(page: page, q: q.trimmed.isEmpty ? nil : q, sort: sort)
            }
        }) { model in StudentsListContent(model: model) }
    }
}

private struct StudentsListContent: View {
    let model: PagedListModel<StudentRow>
    @Environment(Navigator.self) private var nav

    var body: some View {
        ManageListScreen(
            "Students", model: model, key: \.id, emptyTitle: "No students found", searchHint: "Registration no, name or e-mail",
            filters: studentsSorts
        ) { s in
            RecordCard(
                title: s.name ?? s.email,
                subtitle: [s.registrationNumber, s.name != nil ? s.email : nil].compactMap { $0 }.joined(separator: " · "),
                meta: s.createdAt.map { "Joined " + formatDate($0) },
                onClick: { nav.push(.manage(.studentAdmin(id: s.id))) },
                leading: { Avatar(name: s.name ?? s.email, image: s.image) }
            )
        }
        .reloadOnReturn { model.refresh() }
    }
}

// MARK: - profile

@MainActor
@Observable
final class StudentDetailModel {
    let loader: Loader<StudentDetail>
    let payments: Loader<Paged<StudentPayment>>
    let runner: ActionRunner
    var confirmDelete = false
    var removing: StudentEnrollment?

    init(app: AppContainer, id: String) {
        loader = Loader(app: app) { try await $0.service(StudentsAdminAPI.self).get(id).student }
        payments = Loader(app: app) { try await $0.service(StudentsAdminAPI.self).payments(id) }
        runner = ActionRunner(app: app)
    }
}

struct StudentDetailScreen: View {
    let id: String

    var body: some View {
        WithModel({ StudentDetailModel(app: $0, id: id) }) { model in StudentDetailContent(id: id, model: model) }
    }
}

/// The ID card's file name: "ID_Card_<name with underscores>.pdf".
func studentIdCardFileName(_ name: String?) -> String { "ID_Card_\((name ?? "Student").replacingOccurrences(of: " ", with: "_")).pdf" }

private struct StudentDetailContent: View {
    let id: String
    @Bindable var model: StudentDetailModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let runner = model.runner
        ManageScaffold("Student", actions: {
            IconButton(.edit, label: "Edit student") { nav.push(.manage(.studentEdit(id: id))) }
            IconButton(.delete, label: "Delete account") { model.confirmDelete = true }
        }) {
            LoadedColumn(model.loader) { s in
                DetailCard {
                    HStack(alignment: .center, spacing: 14) {
                        Avatar(name: s.name ?? s.email, image: s.image, size: 64)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.name ?? "No name").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                            Text(s.email).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                            if let reg = s.registrationNumber { Text(reg).textStyle(Typo.labelLarge).foregroundStyle(Scheme.primary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !s.profileComplete {
                        Banner("Profile incomplete: the ID card is available once the student completes it.", tone: .warning)
                    }
                    HStack(spacing: 8) {
                        PillOutlinedButton("ID card", icon: .badge, enabled: s.profileComplete && !runner.busy) {
                            let name = studentIdCardFileName(s.name)
                            runner.openFile { try await $0.service(StudentsAdminAPI.self).idCard(id, fileName: name) }
                        }
                        PillOutlinedButton("E-mail it", icon: .mail, enabled: s.profileComplete && !runner.busy) {
                            runner.run({ try await $0.service(StudentsAdminAPI.self).emailIdCard(id) }, success: "ID card e-mailed to \(s.email).")
                        }
                    }
                }
                DetailCard("Profile") {
                    Field("Gender", s.gender == "MALE" ? "Male" : s.gender == "FEMALE" ? "Female" : nil)
                    Field("Father's name", s.fatherName)
                    Field("Date of birth", s.dateOfBirthDisplay)
                    Field("Occupation", s.occupationLabel)
                    Field("Address", s.address)
                    Field("WhatsApp", s.whatsapp)
                    Field("Joined", s.createdAt.map { formatDate($0) })
                }
                DetailCard("Course enrollments") {
                    if s.enrollments.isEmpty {
                        Text("Not enrolled in any course.").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                    ForEach(s.enrollments) { e in
                        HStack(alignment: .center, spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(e.courseTitle).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                                Text("Roll no \(e.rollNumber ?? "—") · since \(formatDate(e.createdAt))")
                                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                                Spacer().frame(height: 4)
                                let tone = statusLabel(e.status)
                                StatusChip(e.statusLabel.trimmed.isEmpty ? tone.0 : e.statusLabel, tone: tone.1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            TextButton("Remove", color: Scheme.error) { model.removing = e }
                        }
                    }
                }
                DetailCard("Payment history") { payments }
            }
        }
        .reloadOnReturn { model.loader.reload(); model.payments.reload() }
        .confirmDialog(
            "Delete this account?",
            message: "The account is removed and its e-mail freed; payment and course records are kept for auditing. Refused while the student has active enrollments, pending fees or payment records.",
            isPresented: $model.confirmDelete, confirm: "Delete", destructive: true
        ) {
            runner.run({ try await $0.service(StudentsAdminAPI.self).delete(id) }, success: "Student account removed.") { _ in nav.pop() }
        }
        .confirmDialog(
            item: $model.removing, title: removeTitle,
            message: { _ in "The student's account is not deleted; they can enrol again later." }, confirm: "Remove", destructive: true
        ) { e in
            runner.run(
                { try await $0.service(EnrollmentsAdminAPI.self).removeEnrollment(e.id, courseId: e.courseId) }, success: "Enrollment removed."
            ) { _ in model.loader.reload() }
        }
    }

    private var removeTitle: String { "Remove from \(model.removing?.courseTitle ?? "")?" }

    @ViewBuilder private var payments: some View {
        switch model.payments.state {
        case .ready(let p):
            if p.data.isEmpty { Text("No payments recorded yet.").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant) }
            ForEach(p.data) { pay in
                VStack(alignment: .leading, spacing: 0) {
                    FieldRow(formatDate(pay.paidAt), rupees(pay.amountInrPaise), strong: true)
                    let line = [pay.courseTitle, pay.description].compactMap { $0 }.joined(separator: " · ")
                    Text(line.trimmed.isEmpty ? "—" : line).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
            }
            if p.totalCount > p.data.count {
                Text("Showing the latest \(p.data.count) of \(p.totalCount).").textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurface)
            }
        case .failed(let message): Text(message).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.error)
        case .loading: Text("Loading…").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurface)
        }
    }
}

// MARK: - edit

@MainActor
@Observable
final class StudentEditModel {
    let id: String
    let loader: Loader<StudentDetail>
    let runner: ActionRunner
    var occupations: [(value: String, label: String)] = []
    var loaded = false
    var name = ""
    var father = ""
    var dob = ""
    var occupation = ""
    var address = ""
    var whatsapp = ""
    var gender = ""
    var replacePhoto = false

    init(app: AppContainer, id: String) {
        self.id = id
        loader = Loader(app: app) { try await $0.service(StudentsAdminAPI.self).get(id).student }
        runner = ActionRunner(app: app)
        Task { [weak self] in
            let config = await app.repo.appConfig().value
            self?.occupations = (config?.lookups.occupations ?? []).map { (value: $0.value, label: $0.label) }
        }
    }

    func fill() {
        guard let s = loader.state.value, !loaded else { return }
        name = s.name ?? ""
        father = s.fatherName ?? ""
        dob = dateOnly(s.dateOfBirth)
        occupation = s.occupation ?? ""
        address = s.address ?? ""
        whatsapp = s.whatsapp ?? ""
        gender = s.gender ?? ""
        loaded = true
    }

    /// The student has a photo of their own (not one of the website's default avatars).
    var hasUploadedPhoto: Bool {
        guard let image = loader.state.value?.image else { return false }
        return !image.trimmed.isEmpty && !image.hasPrefix("/assets/")
    }

    func save(onDone: @escaping () -> Void) {
        let id = id
        let form = formOf { f in
            f.text("name", name); f.text("fatherName", father); f.text("dateOfBirth", dob); f.text("occupation", occupation)
            f.text("address", address); f.text("whatsapp", whatsapp); f.text("gender", gender); f.check("confirmReplacePhoto", replacePhoto)
        }
        runner.run({ try await $0.service(StudentsAdminAPI.self).update(id, form) }, success: "Student details updated.") { _ in onDone() }
    }
}

struct StudentEditScreen: View {
    let id: String

    var body: some View {
        WithModel({ StudentEditModel(app: $0, id: id) }) { model in StudentEditContent(model: model) }
    }
}

private struct StudentEditContent: View {
    @Bindable var model: StudentEditModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = model.loader.state
        let loadError: String? = if case .failed(let message) = state { message } else { nil }
        FormScreen(
            "Edit student", saving: model.runner.busy, canSave: model.loaded, loadError: loadError, onRetry: { model.loader.load() },
            onSave: { model.save { nav.pop() } }
        ) {
            if state.value == nil {
                Text("Loading…").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
            } else {
                FormTextField("Full name", text: $model.name)
                FormTextField("Father's name", text: $model.father)
                FormDateField("Date of birth", value: model.dob) { model.dob = $0 }
                FormDropdown("Gender", options: [(value: "MALE", label: "Male"), (value: "FEMALE", label: "Female")], value: model.gender) {
                    model.gender = $0
                }
                if model.gender == "FEMALE" && model.hasUploadedPhoto {
                    FormCheckbox("Replace the uploaded photo with the female avatar", checked: model.replacePhoto) { model.replacePhoto = $0 }
                }
                FormDropdown("Occupation", options: model.occupations, value: model.occupation) { model.occupation = $0 }
                FormTextField("WhatsApp number", text: $model.whatsapp, supporting: "With country code, e.g. +919876543210", keyboard: .phone)
                FormTextField("Address", text: $model.address, singleLine: false, minLines: 3)
            }
        }
        .onChange(of: state.value?.id, initial: true) { _, _ in model.fill() }
    }
}
