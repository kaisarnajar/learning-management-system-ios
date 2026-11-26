import Observation
import SwiftUI

/*
 * Teachers: /admin/teachers (list), /admin/teachers/[id] (profile) and the add / edit form. Ported from Android's
 * ui/manage/people/Teachers.kt.
 */

private func teacherPublishedChip(_ published: Bool) -> (String, Tone) { published ? ("Published", .success) : ("Draft", .neutral) }

/// Two initials from a name, as the website derives them ("Abdul Rahman" → "AR").
func teacherInitialsOf(_ name: String) -> String {
    let parts = name.trimmed.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.trimmed.isEmpty }
    if parts.isEmpty { return "??" }
    if parts.count == 1 { return String(parts[0].prefix(2)).uppercased() }
    return "\(parts.first!.prefix(1))\(parts.last!.prefix(1))".uppercased()
}

// MARK: - list

struct TeachersListScreen: View {
    var body: some View {
        WithModel({ app in
            PagedListModel<TeacherRow>(app: app) { app, page, q, _ in
                try await app.service(TeachersAdminAPI.self).list(page: page, q: q.trimmed.isEmpty ? nil : q)
            }
        }) { model in TeachersListContent(model: model) }
    }
}

private struct TeachersListContent: View {
    let model: PagedListModel<TeacherRow>
    @Environment(Navigator.self) private var nav

    var body: some View {
        ManageListScreen(
            "Teachers", model: model, key: \.id, emptyTitle: "No teachers yet", searchHint: "Name, e-mail or specialization",
            fab: { AddFab("Add teacher") { nav.push(.manage(.teacherForm())) } }
        ) { t in
            RecordCard(
                title: t.name,
                subtitle: [t.specialization.trimmed.isEmpty ? nil : t.specialization, t.email].compactMap { $0 }.joined(separator: " · "),
                meta: t.createdAt.map { "Added " + formatDate($0) },
                chip: teacherPublishedChip(t.published),
                onClick: { nav.push(.manage(.teacherAdmin(id: t.id))) },
                leading: { Avatar(name: t.name, image: t.imageUrl) }
            )
        }
        .reloadOnReturn { model.refresh() }
    }
}

// MARK: - profile

@MainActor
@Observable
final class TeacherDetailModel {
    let loader: Loader<TeacherDetail>
    let runner: ActionRunner
    var confirmDelete = false

    init(app: AppContainer, id: String) {
        loader = Loader(app: app) { try await $0.service(TeachersAdminAPI.self).get(id).teacher }
        runner = ActionRunner(app: app)
    }
}

struct TeacherDetailScreen: View {
    let id: String

    var body: some View {
        WithModel({ TeacherDetailModel(app: $0, id: id) }) { model in TeacherDetailContent(id: id, model: model) }
    }
}

private struct TeacherDetailContent: View {
    let id: String
    @Bindable var model: TeacherDetailModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        ManageScaffold("Teacher profile", actions: {
            IconButton(.edit, label: "Edit teacher") { nav.push(.manage(.teacherForm(id: id))) }
            IconButton(.delete, label: "Delete teacher") { model.confirmDelete = true }
        }) {
            LoadedColumn(model.loader) { t in
                DetailCard {
                    HStack(alignment: .center, spacing: 14) {
                        Avatar(name: t.name, image: t.imageUrl, size: 72)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.name).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                            Text(t.email ?? "No login email linked").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                            Spacer().frame(height: 4)
                            let chip = teacherPublishedChip(t.published)
                            StatusChip(chip.0, tone: chip.1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                DetailCard("Profile") {
                    Field("Specialization", t.specialization)
                    Field("Initials", t.initials)
                    Field("Bio", t.bio)
                    Field("Registered", t.createdAt.map { formatDate($0) })
                    Field("Profile ID", t.id)
                }
                DetailCard("Courses teaching") {
                    if t.courses.isEmpty {
                        Text("Not assigned to any courses yet.").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                    ForEach(t.courses) { c in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.title).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                            Text([c.category, countOf(c.studentCount, "student")].compactMap { $0 }.joined(separator: " · "))
                                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                            StatusChip(c.statusLabel.trimmed.isEmpty ? c.status : c.statusLabel, tone: courseStatusTone(c.status))
                        }
                    }
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog(deleteTitle, message: deleteMessage, isPresented: $model.confirmDelete, confirm: "Delete", destructive: true) {
            model.runner.run({ try await $0.service(TeachersAdminAPI.self).delete(id) }, success: "Teacher deleted.") { _ in nav.pop() }
        }
    }

    private var teacher: TeacherDetail? { model.loader.state.value }

    private var deleteTitle: String { "Delete \(teacher?.name ?? "this teacher")?" }

    private var deleteMessage: String {
        let n = teacher?.courses.count ?? 0
        return n > 0
            ? "\(teacher?.name ?? "") is assigned to \(countOf(n, "course")). Reassign \(n == 1 ? "it" : "them") to another teacher before deleting."
            : "The teacher profile is removed from the site. Their user account stays."
    }
}

// MARK: - form

@MainActor
@Observable
final class TeacherFormModel {
    let id: String?
    let loader: Loader<TeacherDetail>?
    let runner: ActionRunner
    let account: AccountCheck
    var loaded: Bool
    var specialization = ""
    var bio = ""
    var initials = ""
    var published = true
    var error: String?

    init(app: AppContainer, id: String?) {
        self.id = id
        loader = id.map { id in Loader(app: app) { try await $0.service(TeachersAdminAPI.self).get(id).teacher } }
        runner = ActionRunner(app: app)
        account = AccountCheck(app: app) { app, email in
            AccountAnswer(try await app.service(TeachersAdminAPI.self).lookup(email: email, excludeTeacherId: id).lookup)
        }
        loaded = id == nil
    }

    /// Fills the fields once the teacher has loaded.
    func fill(_ existing: TeacherDetail?) {
        guard let existing, !loaded else { return }
        account.restore(email: existing.email ?? "", name: existing.name)
        specialization = existing.specialization
        bio = existing.bio
        initials = existing.initials
        published = existing.published
        loaded = true
    }

    /// Initials the admin typed are kept; blank ones are filled from the account name.
    func verify() {
        account.verify { [weak self] name in
            guard let self else { return }
            if self.initials.trimmed.isEmpty { self.initials = teacherInitialsOf(name) }
        }
    }

    func save(onDone: @escaping () -> Void) {
        error = if !account.verified { "Verify the account e-mail first." }
            else if specialization.trimmed.isEmpty { "Enter a specialization." }
            else if bio.trimmed.isEmpty { "Enter a bio." }
            else { nil }
        guard error == nil else { return }
        let form = formOf { f in
            f.text("email", account.email.trimmed)
            f.text("specialization", specialization.trimmed)
            f.text("bio", bio.trimmed)
            f.text("initials", initials.trimmed)
            f.check("published", published)
        }
        let id = id
        runner.run({ app in
            let api = app.service(TeachersAdminAPI.self)
            return if let id { try await api.update(id, form) } else { try await api.create(form) }
        }, success: id == nil ? "Teacher created." : "Changes saved.") { _ in onDone() }
    }
}

/// Add ([id] nil) or edit a teacher. The e-mail must belong to a registered account; its name is used.
struct TeacherFormScreen: View {
    let id: String?

    var body: some View {
        WithModel({ TeacherFormModel(app: $0, id: id) }) { model in TeacherFormContent(model: model) }
    }
}

private struct TeacherFormContent: View {
    @Bindable var model: TeacherFormModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let loadState = model.loader?.state
        let loadError: String? = if case .failed(let message) = loadState { message } else { nil }
        let account = model.account
        FormScreen(
            model.id == nil ? "Add teacher" : "Edit teacher", saving: model.runner.busy,
            saveLabel: model.id == nil ? "Create teacher" : "Save changes", error: model.error, canSave: model.loaded,
            loadError: loadError, onRetry: { model.loader?.load() },
            onSave: { model.save { nav.pop() } }
        ) {
            if !model.loaded {
                Text("Loading…").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
            } else {
                if model.id == nil {
                    Text("Link an existing site account by e-mail. The teacher must register first; you assign specialization and public profile details.")
                        .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                }
                FormTextField(
                    "Registered account email", text: account.emailBinding,
                    supporting: "The teacher must already have signed up on the site. We use their account name automatically.",
                    keyboard: .email
                )
                PillOutlinedButton(account.checking ? "Checking…" : "Verify account", enabled: !account.checking && !account.email.trimmed.isEmpty) {
                    model.verify()
                }
                Notice(account.error, tone: .warning)
                Field("Name (from account)", account.name.trimmed.isEmpty ? "Verify the email above to load the account name." : account.name)
                FormTextField("Specialization", text: $model.specialization, supporting: "e.g. Quran & Tajweed")
                FormTextField("Bio", text: $model.bio, singleLine: false, minLines: 4)
                FormTextField(
                    "Initials (avatar)", text: Binding(get: { model.initials }, set: { model.initials = $0.uppercased() }),
                    supporting: "Leave blank to auto-generate from the account name.", capitalization: .characters, maxLength: 4
                )
                FormSwitch("Published on public Teachers page", checked: model.published) { model.published = $0 }
            }
        }
        .onChange(of: model.loader?.state.value?.id, initial: true) { _, _ in model.fill(model.loader?.state.value) }
    }
}
