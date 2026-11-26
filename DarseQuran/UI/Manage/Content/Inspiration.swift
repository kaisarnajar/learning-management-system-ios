import Observation
import SwiftUI

// Website: /admin/daily-inspiration (list, delete), /[id] (view, delete), /new and /[id]/edit. Ported from Android's
// ui/manage/content/Inspiration.kt.

private let inspirationKinds = [("QURAN", "Quranic verse"), ("HADITH", "Hadith")]

private func deleteInspirationTitle(_ kindLabel: String) -> String { "Delete this \(kindLabel.lowercased())?" }
private let deleteInspirationMessage = "The entry is removed for good."

// MARK: - list

@MainActor
final class InspirationListModel {
    let list: PagedListModel<InspirationDto>
    let runner: ActionRunner

    init(app: AppContainer) {
        list = PagedListModel(app: app) { app, page, q, _ in try await app.service(ContentAPI.self).inspirations(page: page, q: q.trimmed.isEmpty ? nil : q) }
        runner = ActionRunner(app: app)
    }
}

struct InspirationListScreen: View {
    var body: some View {
        WithModel({ InspirationListModel(app: $0) }) { model in InspirationListContent(model: model) }
    }
}

private struct InspirationListContent: View {
    let model: InspirationListModel
    @Environment(Navigator.self) private var nav
    @State private var deleting: InspirationDto?

    var body: some View {
        ManageListScreen(
            "Verse & Hadith", model: model.list, key: \.id, emptyTitle: "No verses or hadith posted yet", searchHint: "Search Arabic, translation or reference",
            fab: { AddFab("New post") { nav.push(.manage(.inspirationForm())) } },
            header: {
                Text("Post a Quranic verse or Hadith for the homepage. The latest published entry is shown.")
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        ) { item in
            AppCard(onClick: { nav.push(.manage(.inspirationDetail(id: item.id))) }) {
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(item.kindLabel).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                            StatusChip(item.statusLabel, tone: contentTone(item.statusLabel))
                        }
                        ArabicText(text: item.arabicText.count > 60 ? String(item.arabicText.prefix(60)) + "…" : item.arabicText, size: 20)
                        Text("Updated " + formatDate(item.updatedAt)).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ContentRowMenu([
                        ContentRowAction("View") { nav.push(.manage(.inspirationDetail(id: item.id))) },
                        ContentRowAction("Edit") { nav.push(.manage(.inspirationForm(id: item.id))) },
                        ContentRowAction("Delete", destructive: true) { deleting = item },
                    ])
                }
            }
        }
        .reloadOnReturn { model.list.refresh() }
        .confirmDialog(
            item: $deleting, title: deleteInspirationTitle(deleting?.kindLabel ?? "entry"), message: { _ in deleteInspirationMessage },
            confirm: "Delete", destructive: true
        ) { item in
            model.runner.run({ try await $0.service(ContentAPI.self).deleteInspiration(item.id) }, success: "Entry deleted.") { _ in model.list.refresh() }
        }
    }
}

// MARK: - detail

@MainActor
final class InspirationDetailModel {
    let loader: Loader<InspirationDto>
    let runner: ActionRunner

    init(app: AppContainer, id: String) {
        loader = Loader(app: app) { try await $0.service(ContentAPI.self).inspiration(id).item }
        runner = ActionRunner(app: app)
    }
}

struct InspirationDetailScreen: View {
    let id: String

    var body: some View {
        WithModel({ InspirationDetailModel(app: $0, id: id) }) { model in InspirationDetailContent(id: id, model: model) }
    }
}

private struct InspirationDetailContent: View {
    let id: String
    let model: InspirationDetailModel
    @Environment(Navigator.self) private var nav
    @State private var confirmDelete = false

    var body: some View {
        let item = model.loader.state.value
        ManageScaffold(item.map { "View \($0.kindLabel)" } ?? "Verse & Hadith", actions: {
            IconButton(.edit, label: "Edit") { nav.push(.manage(.inspirationForm(id: id))) }
            IconButton(.delete, label: "Delete") { confirmDelete = true }
        }) {
            LoadedColumn(model.loader) { entry in
                DetailCard {
                    Field("Kind", entry.kindLabel)
                    HStack(spacing: 8) { StatusChip(entry.statusLabel, tone: contentTone(entry.statusLabel)) }
                }
                DetailCard("Arabic text") { ArabicText(text: entry.arabicText) }
                DetailCard("English translation") {
                    Text("“\(entry.englishTranslation)”").textStyle(Typo.bodyLarge).italic().foregroundStyle(Scheme.onSurface)
                }
                if let reference = entry.reference, !reference.trimmed.isEmpty {
                    DetailCard("Reference") { Text(reference).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface) }
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog(
            deleteInspirationTitle(item?.kindLabel ?? "entry"), message: deleteInspirationMessage,
            isPresented: $confirmDelete, confirm: "Delete", destructive: true
        ) {
            let id = id
            model.runner.run({ try await $0.service(ContentAPI.self).deleteInspiration(id) }, success: "Entry deleted.") { _ in nav.pop() }
        }
    }
}

// MARK: - form

@MainActor
@Observable
final class InspirationFormModel {
    let id: String?
    let loader: Loader<InspirationDto?>
    let runner: ActionRunner
    var loaded: Bool
    var kind = "QURAN"
    var arabic = ""
    var english = ""
    var reference = ""
    var published = true

    init(app: AppContainer, id: String?) {
        self.id = id
        loader = Loader(app: app) { app in
            guard let id else { return nil }
            return try await app.service(ContentAPI.self).inspiration(id).item
        }
        runner = ActionRunner(app: app)
        loaded = id == nil
    }

    var item: InspirationDto? { loader.state.value ?? nil }

    func fillOnce() {
        guard let item, !loaded else { return }
        kind = item.kind; arabic = item.arabicText; english = item.englishTranslation; reference = item.reference ?? ""
        published = item.published
        loaded = true
    }

    func save(onDone: @escaping () -> Void) {
        let id = id
        let parts = formOf { f in
            f.text("kind", kind); f.text("arabicText", arabic.trimmed); f.text("englishTranslation", english.trimmed); f.text("reference", reference.trimmed)
            f.check("published", published)
        }
        runner.run({ app in
            let api = app.service(ContentAPI.self)
            return if let id { try await api.updateInspiration(id, parts) } else { try await api.createInspiration(parts) }
        }, success: id == nil ? "Entry created." : "Changes saved.") { _ in onDone() }
    }
}

/// New ([id] nil) or edit verse/hadith.
struct InspirationFormScreen: View {
    let id: String?

    var body: some View {
        WithModel({ InspirationFormModel(app: $0, id: id) }) { model in InspirationFormContent(model: model) }
    }
}

private struct InspirationFormContent: View {
    @Bindable var model: InspirationFormModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = model.loader.state
        let failed: String? = { if case .failed(let m) = state { m } else { nil } }()
        let ready = { if case .ready = state { true } else { false } }()
        FormScreen(
            model.id == nil ? "New verse or hadith" : "Edit verse or hadith",
            saving: model.runner.busy,
            saveLabel: model.id == nil ? "Create entry" : "Save changes",
            canSave: model.loaded && ready,
            loadError: failed,
            onRetry: { model.loader.load() },
            onSave: { model.save { nav.pop() } }
        ) {
            if model.loaded {
                fields
            } else {
                Text(failed != nil ? "" : "Loading…").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
            }
        }
        .onChange(of: model.item != nil, initial: true) { _, ready in if ready { model.fillOnce() } }
    }

    @ViewBuilder private var fields: some View {
        if model.id == nil {
            Text("Add Arabic text and an English translation. Publish when ready to show on the homepage.")
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
        }
        Text("Type").textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurfaceVariant)
        HStack(spacing: 8) {
            ForEach(inspirationKinds, id: \.0) { value, label in
                FilterChip(label: label, selected: model.kind == value) { model.kind = value }
            }
        }
        // Arabic is typed right to left; the preview below shows it as the website sets it.
        OutlinedField(
            label: "Arabic text *", text: Binding(get: { model.arabic }, set: { model.arabic = String($0.prefix(5000)) }),
            placeholder: "النص العربي…", capitalization: .never, autocorrect: false, lines: 4...40
        )
        .environment(\.layoutDirection, .rightToLeft)
        if !model.arabic.trimmed.isEmpty {
            DetailCard("Preview") { ArabicText(text: model.arabic, size: 22) }
        }
        FormTextField("English translation *", text: $model.english, supporting: "English meaning or translation", singleLine: false, minLines: 3, maxLength: 5000)
        FormTextField("Reference (optional)", text: $model.reference, supporting: "e.g. Surah Al-Baqarah 2:255 or Sahih al-Bukhari 1", maxLength: 300)
        FormSwitch("Publish on homepage", checked: model.published, description: "The latest published entry is shown on the homepage.") { model.published = $0 }
    }
}
