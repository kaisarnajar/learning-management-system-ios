import Observation
import SwiftUI

// Website: /admin/announcements (list, homepage toggle, delete), /new and /[id]/edit. Ported from Android's
// ui/manage/content/Announcements.kt.

@MainActor
final class SiteAnnouncementsModel {
    let list: PagedListModel<AnnouncementRow>
    let runner: ActionRunner

    init(app: AppContainer) {
        list = PagedListModel(app: app) { app, page, q, _ in try await app.service(ContentAPI.self).announcements(page: page, q: q.trimmed.isEmpty ? nil : q) }
        runner = ActionRunner(app: app)
    }
}

struct AnnouncementsListScreen: View {
    var body: some View {
        WithModel({ SiteAnnouncementsModel(app: $0) }) { model in SiteAnnouncementsContent(model: model) }
    }
}

private struct SiteAnnouncementsContent: View {
    let model: SiteAnnouncementsModel
    @Environment(Navigator.self) private var nav
    @State private var deleting: AnnouncementRow?

    var body: some View {
        ManageListScreen(
            "Announcements", model: model.list, key: \.id, emptyTitle: "No announcements yet", searchHint: "Search by title, location or text",
            fab: { AddFab("New announcement") { nav.push(.manage(.siteAnnouncementForm())) } },
            header: {
                Text("Academy-wide news: events, scholar visits, masjid programs. Up to 4 published items can be featured on the homepage; every published item appears on the public Announcements page.")
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        ) { a in
            let subtitle = [a.eventDate, a.location].compactMap { $0 }.joined(separator: " · ")
            RecordCard(
                title: a.title,
                subtitle: subtitle.trimmed.isEmpty ? nil : subtitle,
                meta: (["Created " + formatDate(a.createdAt)]
                    + (a.imageCount > 0 ? [a.imageCount == 1 ? "1 image" : "\(a.imageCount) images"] : [])
                    + (a.published ? [] : ["Publish first to feature"])).joined(separator: " · "),
                chip: (a.statusLabel, contentTone(a.statusLabel)),
                onClick: { nav.push(.manage(.siteAnnouncementForm(id: a.id))) },
                leading: {
                    if let thumbnail = a.thumbnail { ContentRowThumbnail(path: thumbnail) } else { RowIcon(.announcement) }
                },
                trailing: {
                    ContentRowMenu([
                        ContentRowAction("Edit") { nav.push(.manage(.siteAnnouncementForm(id: a.id))) },
                        a.published ? ContentRowAction(a.showOnHomepage ? "Remove from homepage" : "Add to homepage") {
                            model.runner.run(
                                { try await $0.service(ContentAPI.self).toggleAnnouncementHomepage(a.id) },
                                success: a.showOnHomepage ? "Removed from the homepage." : "Featured on the homepage."
                            ) { _ in model.list.refresh() }
                        } : nil,
                        a.published ? ContentRowAction("View on website") { openWeb("/announcements/\(a.id)") } : nil,
                        ContentRowAction("Delete", destructive: true) { deleting = a },
                    ])
                }
            )
        }
        .reloadOnReturn { model.list.refresh() }
        .confirmDialog(
            item: $deleting, title: "Delete this announcement?", message: { "\"\($0.title)\" and its images are removed for good." },
            confirm: "Delete", destructive: true
        ) { a in
            model.runner.run({ try await $0.service(ContentAPI.self).deleteAnnouncement(a.id) }, success: "Announcement deleted.") { _ in model.list.refresh() }
        }
    }
}

// MARK: - form

@MainActor
@Observable
final class SiteAnnouncementFormModel {
    let loader: Loader<SiteAnnouncementAdminResponse>
    let runner: ActionRunner
    let files = FormFiles()
    let id: String?
    var loaded = false
    var title = ""
    var body = ""
    var eventDate = ""
    var location = ""
    var published = true
    var homepage = false

    init(app: AppContainer, id: String?) {
        self.id = id
        loader = Loader(app: app) { app in
            let api = app.service(ContentAPI.self)
            if let id { return try await api.announcement(id) }
            let limits = try await api.announcementLimits()
            return SiteAnnouncementAdminResponse(
                announcement: AnnouncementDetail(id: ""), featuredCount: limits.featuredCount, featuredMax: limits.featuredMax, maxImages: limits.maxImages
            )
        }
        runner = ActionRunner(app: app)
    }

    func fillOnce() {
        guard let a = loader.state.value?.announcement, !loaded else { return }
        if id != nil {
            title = a.title; body = a.body; eventDate = a.eventDateInput ?? ""; location = a.location ?? ""
            published = a.published; homepage = a.showOnHomepage
        }
        loaded = true
    }

    func save(onDone: @escaping () -> Void) {
        let (removed, picked) = (files.removed, files.picked)
        let parts = formOf { f in
            f.text("title", title.trimmed); f.text("body", body); f.text("eventDate", eventDate); f.text("location", location.trimmed)
            f.check("published", published); f.check("showOnHomepage", homepage)
            f.texts("removeImage", removed.sorted())
            picked.forEach { f.file("images", $0) }
        }
        let id = id
        runner.run({ app in
            let api = app.service(ContentAPI.self)
            return if let id { try await api.updateAnnouncement(id, parts) } else { try await api.createAnnouncement(parts) }
        }, success: id == nil ? "Announcement created." : "Announcement updated.") { _ in onDone() }
    }
}

/// New ([id] nil) or edit announcement.
struct SiteAnnouncementFormScreen: View {
    let id: String?

    var body: some View {
        WithModel({ SiteAnnouncementFormModel(app: $0, id: id) }) { model in SiteAnnouncementFormContent(id: id, model: model) }
    }
}

private struct SiteAnnouncementFormContent: View {
    let id: String?
    @Bindable var model: SiteAnnouncementFormModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = model.loader.state
        let failed: String? = { if case .failed(let m) = state { m } else { nil } }()
        FormScreen(
            id == nil ? "New announcement" : "Edit announcement",
            saving: model.runner.busy,
            saveLabel: id == nil ? "Publish announcement" : "Save changes",
            canSave: model.loaded,
            loadError: failed,
            onRetry: { model.loader.load() },
            onSave: { model.save { nav.pop() } }
        ) {
            if let data = state.value {
                fields(data)
            } else {
                Text(failed != nil ? "" : "Loading…").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
            }
        }
        .onChange(of: state.value != nil, initial: true) { _, ready in if ready { model.fillOnce() } }
    }

    @ViewBuilder private func fields(_ data: SiteAnnouncementAdminResponse) -> some View {
        if id == nil {
            Text("Share events such as guest scholars at a masjid. Use \"Show on homepage\" to feature up to \(data.featuredMax) items; every published item appears on the Announcements page.")
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
        }
        FormTextField("Title", text: $model.title, supporting: "e.g. Guest Mufti visit — Masjid Al-Noor", maxLength: 200)
        FormDateField("Event date (optional)", value: model.eventDate, clearable: true) { model.eventDate = $0 }
        FormTextField("Location (optional)", text: $model.location, supporting: "e.g. Masjid Al-Noor, Srinagar", maxLength: 200)
        FormTextField("Announcement", text: $model.body, supporting: "Full details for students and visitors (at least 10 characters).", singleLine: false, minLines: 6)
        ContentImagesField(
            label: id == nil ? "Screenshots & photos (optional)" : "Screenshots & photos",
            current: data.announcement.images, removed: model.files.removed, onRemovedChange: { model.files.removed = $0 },
            picked: model.files.picked, onPickedChange: { model.files.picked = $0 }, max: data.maxImages
        )
        FormSection("Visibility") {
            FeaturedSwitch(
                featured: model.homepage, currentlyFeatured: data.announcement.showOnHomepage, used: data.featuredCount, max: data.featuredMax,
                section: "Featured Announcements", pageName: "Announcements page", noun: "announcements"
            ) { model.homepage = $0 }
            FormSwitch(
                "Published", checked: model.published,
                description: "Turn off to save as a draft (hidden from the public site). Publishing notifies every student."
            ) { model.published = $0; if !$0 { model.homepage = false } }
        }
    }
}
