import Observation
import SwiftUI

// Website: /admin/library (list, delete), /[id] (view, delete), /new and /[id]/edit (cover image upload). Ported from
// Android's ui/manage/content/Library.kt.

private func libraryTone(_ item: LibraryItemDto) -> Tone { item.published ? .info : .neutral }

/// A library item's cover, or the book icon when it has none.
private struct LibraryCover: View {
    let path: String?
    var width: CGFloat = 36
    var height: CGFloat = 48

    var body: some View {
        if let path {
            RemoteImage(path: path).frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                .accessibilityHidden(true)
        } else {
            RowIcon(.courses)
        }
    }
}

private func deleteLibraryMessage(_ title: String) -> String { "\"\(title)\" and its cover are removed from the library for good." }

// MARK: - list

@MainActor
final class ManageLibraryListModel {
    let list: PagedListModel<LibraryItemDto>
    let runner: ActionRunner

    init(app: AppContainer) {
        list = PagedListModel(app: app) { app, page, q, _ in try await app.service(ContentAPI.self).library(page: page, q: q.trimmed.isEmpty ? nil : q) }
        runner = ActionRunner(app: app)
    }
}

// ManageLibraryListScreen is Android's LibraryListScreen; renamed because the student app's library list has that name.
struct ManageLibraryListScreen: View {
    var body: some View {
        WithModel({ ManageLibraryListModel(app: $0) }) { model in ManageLibraryListContent(model: model) }
    }
}

private struct ManageLibraryListContent: View {
    let model: ManageLibraryListModel
    @Environment(Navigator.self) private var nav
    @State private var deleting: LibraryItemDto?

    var body: some View {
        ManageListScreen(
            "Library", model: model.list, key: \.id, emptyTitle: "No library items yet", searchHint: "Search by title, author or topic",
            fab: { AddFab("Add item") { nav.push(.manage(.libraryForm())) } }
        ) { item in
            RecordCard(
                title: item.title,
                subtitle: "\(item.author) · \(item.topic)",
                meta: [item.level, item.language, item.featuredOnHomepage ? "Featured" : "Not featured"].joined(separator: " · "),
                chip: (item.statusLabel, libraryTone(item)),
                onClick: { nav.push(.manage(.libraryAdminDetail(id: item.id))) },
                leading: { LibraryCover(path: item.imagePath) },
                trailing: {
                    ContentRowMenu([
                        ContentRowAction("View") { nav.push(.manage(.libraryAdminDetail(id: item.id))) },
                        ContentRowAction("Edit") { nav.push(.manage(.libraryForm(id: item.id))) },
                        ContentRowAction("Delete", destructive: true) { deleting = item },
                    ])
                }
            )
        }
        .reloadOnReturn { model.list.refresh() }
        .confirmDialog(item: $deleting, title: "Delete this item?", message: { deleteLibraryMessage($0.title) }, confirm: "Delete", destructive: true) { item in
            model.runner.run({ try await $0.service(ContentAPI.self).deleteLibraryItem(item.id) }, success: "Item deleted.") { _ in model.list.refresh() }
        }
    }
}

// MARK: - detail

@MainActor
final class LibraryDetailModel {
    let loader: Loader<LibraryItemDto>
    let runner: ActionRunner

    init(app: AppContainer, id: String) {
        loader = Loader(app: app) { try await $0.service(ContentAPI.self).libraryItem(id).item }
        runner = ActionRunner(app: app)
    }
}

struct LibraryDetailScreen: View {
    let id: String

    var body: some View {
        WithModel({ LibraryDetailModel(app: $0, id: id) }) { model in LibraryDetailContent(id: id, model: model) }
    }
}

private struct LibraryDetailContent: View {
    let id: String
    let model: LibraryDetailModel
    @Environment(Navigator.self) private var nav
    @State private var confirmDelete = false

    var body: some View {
        ManageScaffold("Library item", actions: {
            IconButton(.edit, label: "Edit item") { nav.push(.manage(.libraryForm(id: id))) }
            IconButton(.delete, label: "Delete item") { confirmDelete = true }
        }) {
            LoadedColumn(model.loader) { item in
                DetailCard {
                    HStack(alignment: .center, spacing: 14) {
                        LibraryCover(path: item.imagePath, width: 96, height: 128)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                            Text("\(item.author) · \(item.topic)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                            StatusChip(item.statusLabel, tone: libraryTone(item))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                DetailCard {
                    Field("Title", item.title)
                    Field("Author", item.author)
                    Field("Topic", item.topic)
                    Field("Level", item.level)
                    Field("Language", item.language)
                    Field("Homepage", item.featuredOnHomepage ? "Featured" : "Not featured")
                    Field("PDF", item.pdfUrl)
                    if let pdf = item.pdfUrl, !pdf.trimmed.isEmpty {
                        PillOutlinedButton("Open PDF", icon: .pdf) { openWeb(pdf) }
                    }
                    Field("Added", formatDate(item.createdAt))
                    Field("ID", item.id)
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog(
            "Delete this item?", message: deleteLibraryMessage(model.loader.state.value?.title ?? "This item"),
            isPresented: $confirmDelete, confirm: "Delete", destructive: true
        ) {
            let id = id
            model.runner.run({ try await $0.service(ContentAPI.self).deleteLibraryItem(id) }, success: "Item deleted.") { _ in nav.pop() }
        }
    }
}

// MARK: - form

/// A choice from [options] where "Other" lets the admin type their own value (the website form's topic/language).
private struct LibraryChoiceWithOther: View {
    let label: String
    let options: [String]
    @Binding var value: String
    @Binding var custom: Bool

    var body: some View {
        // "Other" is always offered: with an empty library the server's topic list is empty, and there was no way in.
        let choices = (!value.trimmed.isEmpty && !custom && !options.contains(value) ? [value] : []) + withOther(options)
        FormDropdown(label, options: choices.map { (value: $0, label: $0) }, value: custom ? "Other" : value, placeholder: "Select…") { picked in
            if picked == "Other" { custom = true; value = "" } else { custom = false; value = picked }
        }
        if custom { FormTextField("Specify \(label.lowercased())", text: $value, maxLength: 100) }
    }
}

@MainActor
@Observable
final class LibraryFormModel {
    let id: String?
    let loader: Loader<(LibraryItemDto?, LibraryOptions)>
    let runner: ActionRunner
    let files = FormFiles()
    var loaded: Bool
    var title = ""
    var author = ""
    var topic = ""
    var customTopic = false
    var level = "Beginner"
    var language = ""
    var customLanguage = false
    var pdfUrl = ""
    var published = true
    var featured = false
    var removeCover = false

    init(app: AppContainer, id: String?) {
        self.id = id
        loader = Loader(app: app) { app in
            let api = app.service(ContentAPI.self)
            if let id {
                let r = try await api.libraryItem(id)
                return (r.item, r.options)
            }
            return (nil, try await api.libraryOptions())
        }
        runner = ActionRunner(app: app)
        loaded = id == nil
    }

    var item: LibraryItemDto? { loader.state.value?.0 }
    var options: LibraryOptions? { loader.state.value?.1 }

    func fillOnce() {
        guard let item, !loaded else { return }
        title = item.title; author = item.author; topic = item.topic; level = item.level; language = item.language
        pdfUrl = item.pdfUrl ?? ""; published = item.published; featured = item.featuredOnHomepage
        loaded = true
    }

    func save(onDone: @escaping () -> Void) {
        let (id, cover, removeCover) = (id, files.single, removeCover)
        let parts = formOf { f in
            f.text("title", title.trimmed); f.text("author", author.trimmed); f.text("topic", topic.trimmed); f.text("level", level)
            f.text("language", language.trimmed); f.text("pdfUrl", pdfUrl.trimmed)
            f.check("published", published); f.check("featuredOnHomepage", featured)
            f.file("image", cover)
            if id != nil { f.text("removeImage", removeCover && cover == nil ? "true" : "false") }
        }
        runner.run({ app in
            let api = app.service(ContentAPI.self)
            return if let id { try await api.updateLibraryItem(id, parts) } else { try await api.createLibraryItem(parts) }
        }, success: id == nil ? "Item created." : "Changes saved.") { _ in onDone() }
    }
}

/// New ([id] nil) or edit library item.
struct LibraryFormScreen: View {
    let id: String?

    var body: some View {
        WithModel({ LibraryFormModel(app: $0, id: id) }) { model in LibraryFormContent(model: model) }
    }
}

private struct LibraryFormContent: View {
    @Bindable var model: LibraryFormModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = model.loader.state
        let failed: String? = { if case .failed(let m) = state { m } else { nil } }()
        FormScreen(
            model.id == nil ? "Add library item" : "Edit library item",
            saving: model.runner.busy,
            saveLabel: model.id == nil ? "Create item" : "Save changes",
            canSave: model.loaded && state.value != nil,
            loadError: failed,
            onRetry: { model.loader.load() },
            onSave: { model.save { nav.pop() } }
        ) {
            if let options = model.options, model.loaded {
                fields(options)
            } else {
                Text(failed != nil ? "" : "Loading…").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
            }
        }
        .onChange(of: model.item != nil, initial: true) { _, ready in if ready { model.fillOnce() } }
    }

    @ViewBuilder private func fields(_ options: LibraryOptions) -> some View {
        let item = model.item
        FormImageField(
            "Cover image (optional, max 2 MB)",
            currentUrl: model.removeCover ? nil : item?.imagePath,
            picked: model.files.single,
            onRemoveCurrent: item?.imagePath != nil ? { model.removeCover = true } : nil
        ) { model.files.single = $0 }
        FormTextField("Title", text: $model.title)
        FormTextField("Author", text: $model.author)
        LibraryChoiceWithOther(label: "Topic", options: options.topics, value: $model.topic, custom: $model.customTopic)
        FormDropdown("Level", options: options.levels.map { (value: $0, label: $0) }, value: model.level) { model.level = $0 }
        LibraryChoiceWithOther(label: "Language", options: options.languages, value: $model.language, custom: $model.customLanguage)
        FormTextField("PDF URL", text: $model.pdfUrl, supporting: "Link to the PDF, starting with https://", keyboard: .uri)
        FormSection("Visibility") {
            FormSwitch("Published", checked: model.published, description: "Turn off to hide from the public library.") { model.published = $0 }
            FeaturedSwitch(
                featured: model.featured, currentlyFeatured: item?.featuredOnHomepage == true, used: options.featuredCount, max: options.featuredMax,
                section: "Featured Resources", pageName: "library", noun: "resources"
            ) { model.featured = $0 }
        }
        if let item { Text("ID: \(item.id)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant) }
    }
}
