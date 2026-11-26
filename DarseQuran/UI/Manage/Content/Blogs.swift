import Observation
import SwiftUI

// Website: /admin/blogs (+ new, [id]/edit), /admin/blog-approvals (+ [id]), /teacher/blogs (+ new, [id]/edit). Ported
// from Android's ui/manage/content/Blogs.kt.

/// Who is editing a blog post: the admin, or a teacher writing their own (Android's BlogEditorMode).
enum BlogEditorMode: Hashable, Sendable { case admin, teacher }

private func blogMetaLine(_ row: BlogRow, withAuthor: Bool) -> String {
    var parts: [String] = []
    if withAuthor, let author = row.authorName { parts.append(author) }
    parts.append(formatDate(row.createdAt))
    if row.imageCount > 0 { parts.append(row.imageCount == 1 ? "1 image" : "\(row.imageCount) images") }
    if row.featuredOnHomepage { parts.append("Featured") }
    return parts.joined(separator: " · ")
}

private struct BlogLeading: View {
    let row: BlogRow
    var body: some View {
        if let thumbnail = row.thumbnail { ContentRowThumbnail(path: thumbnail) } else { RowIcon(.blog) }
    }
}

private func deleteBlogMessage(_ title: String) -> String { "\"\(title)\", its images, likes and comments are removed for good." }

// MARK: - admin list

@MainActor
final class BlogsAdminModel {
    let list: PagedListModel<BlogRow>
    let runner: ActionRunner

    init(app: AppContainer) {
        list = PagedListModel(app: app) { app, page, q, _ in try await app.service(ContentAPI.self).blogs(page: page, q: q.trimmed.isEmpty ? nil : q) }
        runner = ActionRunner(app: app)
    }
}

struct BlogsListScreen: View {
    var body: some View {
        WithModel({ BlogsAdminModel(app: $0) }) { model in BlogsListContent(model: model) }
    }
}

private struct BlogsListContent: View {
    let model: BlogsAdminModel
    @Environment(Navigator.self) private var nav
    @State private var deleting: BlogRow?

    var body: some View {
        ManageListScreen(
            "Blogs", model: model.list, key: \.id, emptyTitle: "No blog posts yet", searchHint: "Search by title or author",
            fab: { AddFab("New blog post") { nav.push(.manage(.blogForm())) } },
            header: {
                Text("Write articles, or review teacher submissions in Blog approvals.")
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        ) { post in
            RecordCard(
                title: post.title,
                subtitle: post.excerpt,
                meta: blogMetaLine(post, withAuthor: true),
                chip: (post.statusLabel, contentTone(post.statusLabel)),
                onClick: { nav.push(.manage(.blogForm(id: post.id))) },
                leading: { BlogLeading(row: post) },
                trailing: {
                    ContentRowMenu([
                        ContentRowAction("Edit") { nav.push(.manage(.blogForm(id: post.id))) },
                        post.publicPath.map { path in ContentRowAction("View on website") { openWeb(path) } },
                        ContentRowAction("Delete", destructive: true) { deleting = post },
                    ])
                }
            )
        }
        .reloadOnReturn { model.list.refresh() }
        .confirmDialog(item: $deleting, title: "Delete this blog post?", message: { deleteBlogMessage($0.title) }, confirm: "Delete", destructive: true) { post in
            model.runner.run({ try await $0.service(ContentAPI.self).deleteBlog(post.id) }, success: "Blog post deleted.") { _ in model.list.refresh() }
        }
    }
}

// MARK: - teacher list

@MainActor
final class TeacherBlogsModel {
    let list: PagedListModel<BlogRow>
    let runner: ActionRunner

    init(app: AppContainer) {
        list = PagedListModel(app: app) { app, page, _, _ in try await app.service(ContentAPI.self).teacherBlogs(page: page) }
        runner = ActionRunner(app: app)
    }
}

struct TeacherBlogsListScreen: View {
    var body: some View {
        WithModel({ TeacherBlogsModel(app: $0) }) { model in TeacherBlogsListContent(model: model) }
    }
}

private struct TeacherBlogsListContent: View {
    let model: TeacherBlogsModel
    @Environment(Navigator.self) private var nav
    @State private var deleting: BlogRow?

    var body: some View {
        ManageListScreen(
            "My blog posts", model: model.list, key: \.id, emptyTitle: "You have not written any blog posts yet", searchHint: nil,
            fab: { AddFab("New blog post") { nav.push(.manage(.teacherBlogForm())) } },
            header: {
                Text("Write articles for the academy blog. Posts are reviewed by an admin before they go live.")
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        ) { post in
            RecordCard(
                title: post.title,
                subtitle: post.excerpt,
                meta: "Updated " + formatDate(post.updatedAt) + (!post.canEdit ? " · Approved posts can no longer be edited" : ""),
                chip: (post.statusLabel, contentTone(post.statusLabel)),
                onClick: post.canEdit ? { nav.push(.manage(.teacherBlogForm(id: post.id))) }
                    : post.publicPath.map { path in { openWeb(path) } },
                leading: { BlogLeading(row: post) },
                trailing: {
                    ContentRowMenu([
                        post.canEdit ? ContentRowAction("Edit") { nav.push(.manage(.teacherBlogForm(id: post.id))) } : nil,
                        post.publicPath.map { path in ContentRowAction("View on website") { openWeb(path) } },
                        post.canDelete ? ContentRowAction("Delete", destructive: true) { deleting = post } : nil,
                    ])
                }
            )
        }
        .reloadOnReturn { model.list.refresh() }
        .confirmDialog(item: $deleting, title: "Delete this blog post?", message: { deleteBlogMessage($0.title) }, confirm: "Delete", destructive: true) { post in
            model.runner.run({ try await $0.service(ContentAPI.self).deleteTeacherBlog(post.id) }, success: "Blog post deleted.") { _ in model.list.refresh() }
        }
    }
}

// MARK: - editor

@MainActor
@Observable
final class BlogEditorModel {
    let mode: BlogEditorMode
    let id: String?
    let loader: Loader<BlogResponse>
    let runner: ActionRunner
    let files = FormFiles()
    var loaded: Bool
    var title = ""
    var excerpt = ""
    var body = ""
    var published = false
    var featured = false

    init(app: AppContainer, mode: BlogEditorMode, id: String?) {
        self.mode = mode
        self.id = id
        let admin = mode == .admin
        loader = Loader(app: app) { app in
            let api = app.service(ContentAPI.self)
            if let id { return admin ? try await api.blog(id) : try await api.teacherBlog(id) }
            let limits = admin ? try await api.blogLimits() : try await api.teacherBlogLimits()
            return BlogResponse(post: BlogDetail(id: ""), featuredCount: limits.featuredCount, featuredMax: limits.featuredMax, maxImages: limits.maxImages)
        }
        runner = ActionRunner(app: app)
        loaded = id == nil
    }

    var admin: Bool { mode == .admin }
    var post: BlogDetail? { loader.state.value?.post }
    /// Admin: a teacher's submission, whose text and images can't be changed.
    var readOnly: Bool { admin && post?.contentReadOnly == true }
    /// Teacher: an approved post.
    var locked: Bool { !admin && id != nil && post?.canEdit == false }

    func fillOnce() {
        guard let post, !loaded else { return }
        title = post.title; excerpt = post.excerpt ?? ""; body = post.body
        published = post.published; featured = post.featuredOnHomepage
        loaded = true
    }

    func save(onDone: @escaping () -> Void) {
        if locked { runner.message("This post can no longer be edited because it has been approved."); return }
        // A teacher's submission keeps its text: send it back unchanged, as the website's read-only inputs do.
        let bodyHtml = readOnly ? (post?.body ?? "") : toWebsiteHtml(body)
        if !readOnly && isBlankHtml(bodyHtml) { runner.message("Write the blog content first."); return }
        let (admin, readOnly, removed, picked) = (admin, readOnly, files.removed, files.picked)
        let parts = formOf { f in
            f.text("title", title.trimmed); f.text("excerpt", excerpt.trimmed); f.text("body", bodyHtml)
            if admin { f.check("published", published); f.check("featuredOnHomepage", featured) }
            if !readOnly { f.texts("removeImage", removed.sorted()); picked.forEach { f.file("images", $0) } }
        }
        let id = id
        runner.run({ app in
            let s = app.service(ContentAPI.self)
            switch (admin, id) {
            case (true, nil): return try await s.createBlog(parts)
            case (true, let id?): return try await s.updateBlog(id, parts)
            case (false, nil): return try await s.createTeacherBlog(parts)
            case (false, let id?): return try await s.updateTeacherBlog(id, parts)
            }
        }, success: !admin && id == nil ? "Your blog post was submitted for admin approval."
            : !admin ? "Your changes were resubmitted for admin approval."
            : id == nil ? "Blog post created."
            : "Changes saved.") { _ in onDone() }
    }

    func delete(onDone: @escaping () -> Void) {
        guard let id else { return }
        let admin = admin
        runner.run({ app in
            admin ? try await app.service(ContentAPI.self).deleteBlog(id) : try await app.service(ContentAPI.self).deleteTeacherBlog(id)
        }, success: "Blog post deleted.") { _ in onDone() }
    }
}

/// A new or edited post, for admins (publish and homepage switches; a teacher's submission is read-only apart from
/// those) and teachers (always sent for approval; approved posts are locked).
struct BlogEditorScreen: View {
    let mode: BlogEditorMode
    let id: String?

    var body: some View {
        WithModel({ BlogEditorModel(app: $0, mode: mode, id: id) }) { model in BlogEditorContent(model: model) }
    }
}

private struct BlogEditorContent: View {
    @Bindable var model: BlogEditorModel
    @Environment(Navigator.self) private var nav
    @State private var confirmDelete = false

    var body: some View {
        let state = model.loader.state
        let failed: String? = { if case .failed(let m) = state { m } else { nil } }()
        let id = model.id
        FormScreen(
            model.readOnly ? "Review blog post" : id == nil ? "New blog post" : "Edit blog post",
            saving: model.runner.busy,
            saveLabel: !model.admin && id == nil ? "Submit for approval"
                : !model.admin ? "Resubmit for approval"
                : id == nil ? "Create blog post"
                : "Save changes",
            canSave: model.loaded && state.value != nil,
            loadError: failed,
            onRetry: { model.loader.load() },
            onSave: { model.save { nav.pop() } }
        ) {
            if let data = state.value, model.loaded {
                fields(data)
            } else {
                Text(failed != nil ? "" : "Loading…").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
            }
        }
        .onChange(of: model.post != nil, initial: true) { _, ready in if ready { model.fillOnce() } }
        .confirmDialog(
            "Delete this blog post?", message: deleteBlogMessage(model.title), isPresented: $confirmDelete, confirm: "Delete", destructive: true
        ) { model.delete { nav.pop() } }
    }

    @ViewBuilder private func fields(_ data: BlogResponse) -> some View {
        let id = model.id
        let post = model.post
        let readOnly = model.readOnly
        let locked = model.locked
        if id == nil {
            Text(
                model.admin
                    ? "Write your article and attach screenshots or photos. Use \"Show on homepage\" to feature up to \(data.featuredMax) published posts; all published posts appear on the Blog page."
                    : "Share guidance or reflections with students. Your post will be reviewed before it appears on the public blog."
            )
            .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
        }
        if let post, id != nil {
            HStack(spacing: 8) {
                StatusChip(post.statusLabel, tone: contentTone(post.statusLabel))
                if let author = post.authorName { Text("by \(author)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant) }
            }
        }
        if readOnly {
            Banner(
                "This post was submitted by a teacher for approval. Title, summary, content and images cannot be changed here. You can update publishing and homepage settings below, or use Approve / Reject on Blog approvals.",
                tone: .warning
            )
        }
        if locked { Banner("This post can no longer be edited because it has been approved.", tone: .warning) }

        FormTextField(
            "Title", text: $model.title, supporting: "At least 3 characters, e.g. Tips for memorizing Quran with tajweed",
            enabled: !readOnly && !locked, maxLength: 200
        )
        FormTextField(
            "Short summary (optional)", text: $model.excerpt, supporting: "A brief line shown on the blog listing page.", singleLine: false, minLines: 2,
            enabled: !readOnly && !locked, maxLength: 400
        )
        if readOnly || locked {
            DetailCard("Blog content") { HtmlText(html: model.body) }
        } else {
            RichTextField("Blog content", initialHtml: model.body) { model.body = $0 }
            Text("At least 20 characters. You can add screenshots below.").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
        }
        ContentImagesField(
            label: id == nil ? "Screenshots & photos (optional)" : "Screenshots & photos",
            current: post?.images ?? [], removed: model.files.removed, onRemovedChange: { model.files.removed = $0 },
            picked: model.files.picked, onPickedChange: { model.files.picked = $0 }, max: data.maxImages, readOnly: readOnly || locked
        )
        if model.admin {
            FormSection("Publishing") {
                FormSwitch("Publish on the public blog", checked: model.published, description: "Leave off to save as a draft.") { model.published = $0 }
                FeaturedSwitch(
                    featured: model.featured, currentlyFeatured: post?.featuredOnHomepage == true, used: data.featuredCount, max: data.featuredMax,
                    section: "Featured Blogs", pageName: "Blog page", noun: "posts"
                ) { model.featured = $0 }
            }
        } else if !locked {
            Banner("Your post will be sent to the admin for review. Once approved, it will appear on the public blog page.", tone: .warning)
        }
        if id != nil && (model.admin || post?.canDelete == true) {
            TextButton("Delete this post", color: Scheme.error) { confirmDelete = true }
        }
    }
}

// MARK: - approvals

@MainActor
final class BlogApprovalsModel {
    let list: PagedListModel<BlogRow>
    let runner: ActionRunner

    init(app: AppContainer) {
        list = PagedListModel(app: app) { app, page, q, _ in try await app.service(ContentAPI.self).blogApprovals(page: page, q: q.trimmed.isEmpty ? nil : q) }
        runner = ActionRunner(app: app)
    }
}

/// A post being approved (true) or rejected (false).
private struct BlogDecision: Identifiable {
    let post: BlogRow?
    let approve: Bool
    var id: String { "\(post?.id ?? "")-\(approve)" }
}

private func approvalTitle(_ approve: Bool) -> String { approve ? "Approve blog post" : "Reject blog post" }
private func approvalMessage(_ approve: Bool) -> String {
    approve
        ? "Approve this blog post and publish it on the public blog?"
        : "Reject this blog post and mark it as declined? The teacher can edit and resubmit it."
}

struct BlogApprovalsListScreen: View {
    var body: some View {
        WithModel({ BlogApprovalsModel(app: $0) }) { model in BlogApprovalsContent(model: model) }
    }
}

private struct BlogApprovalsContent: View {
    let model: BlogApprovalsModel
    @Environment(Navigator.self) private var nav
    @State private var deciding: BlogDecision?

    var body: some View {
        ManageListScreen(
            "Blog approvals", model: model.list, key: \.id, emptyTitle: "No teacher blog posts awaiting approval", searchHint: "Search by title or author",
            header: {
                Text("Review blog posts submitted by teachers before they appear on the public blog. Admin posts are published directly from Blogs.")
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        ) { post in
            let who = [post.authorName, post.authorEmail].compactMap { $0 }.joined(separator: " · ")
            RecordCard(
                title: post.title,
                subtitle: who.trimmed.isEmpty ? nil : who,
                meta: "Submitted " + formatDate(post.createdAt) + " · " + (post.imageCount == 1 ? "1 image" : "\(post.imageCount) images"),
                chip: (post.statusLabel, contentTone(post.statusLabel)),
                onClick: { nav.push(.manage(.blogApproval(id: post.id))) },
                leading: { BlogLeading(row: post) },
                trailing: {
                    ContentRowMenu([
                        ContentRowAction("View") { nav.push(.manage(.blogApproval(id: post.id))) },
                        ContentRowAction("Edit") { nav.push(.manage(.blogForm(id: post.id))) },
                        ContentRowAction("Approve") { deciding = BlogDecision(post: post, approve: true) },
                        ContentRowAction("Reject", destructive: true) { deciding = BlogDecision(post: post, approve: false) },
                    ])
                }
            )
        }
        .reloadOnReturn { model.list.refresh() }
        .blogApprovalDialog($deciding) { decision in
            guard let post = decision.post else { return }
            let approve = decision.approve
            model.runner.run(
                { approve ? try await $0.service(ContentAPI.self).approveBlog(post.id) : try await $0.service(ContentAPI.self).rejectBlog(post.id) },
                success: approve ? "Blog post approved and published." : "Blog post rejected. The teacher can edit and resubmit."
            ) { _ in model.list.refresh() }
        }
    }
}

private extension View {
    /// Asks before approving or rejecting (Android's ApprovalDialog).
    func blogApprovalDialog(_ deciding: Binding<BlogDecision?>, onConfirm: @escaping (BlogDecision) -> Void) -> some View {
        let shown = Binding(get: { deciding.wrappedValue != nil }, set: { if !$0 { deciding.wrappedValue = nil } })
        let approve = deciding.wrappedValue?.approve ?? true
        return alert(approvalTitle(approve), isPresented: shown, presenting: deciding.wrappedValue) { d in
            Button("Cancel", role: .cancel) {}
            Button(d.approve ? "Approve" : "Reject", role: d.approve ? nil : .destructive) { onConfirm(d) }
        } message: { d in
            Text(approvalMessage(d.approve))
        }
    }
}

@MainActor
final class BlogApprovalDetailModel {
    let loader: Loader<BlogDetail>
    let runner: ActionRunner

    init(app: AppContainer, id: String) {
        loader = Loader(app: app) { try await $0.service(ContentAPI.self).blogApproval(id).post }
        runner = ActionRunner(app: app)
    }
}

struct BlogApprovalDetailScreen: View {
    let id: String

    var body: some View {
        WithModel({ BlogApprovalDetailModel(app: $0, id: id) }) { model in BlogApprovalDetailContent(id: id, model: model) }
    }
}

private struct BlogApprovalDetailContent: View {
    let id: String
    let model: BlogApprovalDetailModel
    @Environment(Navigator.self) private var nav
    @State private var deciding: BlogDecision?

    var body: some View {
        ManageScaffold("Blog approval", actions: {
            IconButton(.edit, label: "Edit") { nav.push(.manage(.blogForm(id: id))) }
        }) {
            LoadedColumn(model.loader) { post in
                DetailCard {
                    Text(post.title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                    Text(
                        "Submitted by " + (post.authorName ?? post.authorEmail ?? "Teacher")
                            + (post.authorName != nil && post.authorEmail != nil ? " · \(post.authorEmail!)" : "")
                    )
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    HStack(spacing: 8) {
                        Button { deciding = BlogDecision(post: nil, approve: true) } label: {
                            HStack(spacing: 8) {
                                Icon.check.image.font(.system(size: 16, weight: .semibold))
                                Text("Approve").textStyle(Typo.labelLarge)
                            }
                            .padding(.leading, 16).padding(.trailing, 24)
                            .frame(minHeight: 40)
                        }
                        .buttonStyle(FilledStyle(background: Brand.cta, foreground: Brand.onCta, radius: 20))
                        .disabled(model.runner.busy)
                        ContentOutlinedButton("Reject", icon: .close, color: Scheme.error, enabled: !model.runner.busy) {
                            deciding = BlogDecision(post: nil, approve: false)
                        }
                        Spacer(minLength: 0)
                    }
                }
                DetailCard {
                    Field("Submitted", formatDate(post.createdAt))
                    Field("Images", "\(post.images.count)")
                    Field("Excerpt", post.excerpt, showEmpty: false)
                }
                DetailCard("Content") { HtmlText(html: post.body) }
                if !post.images.isEmpty {
                    DetailCard("Images") {
                        ForEach(post.images) { img in
                            RemoteImage(path: img.imagePath, contentDescription: img.caption)
                                .frame(maxWidth: .infinity).frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            if let caption = img.caption { Text(caption).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurface) }
                        }
                    }
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .blogApprovalDialog($deciding) { decision in
            let approve = decision.approve
            model.runner.run(
                { approve ? try await $0.service(ContentAPI.self).approveBlog(id) : try await $0.service(ContentAPI.self).rejectBlog(id) },
                success: approve ? "Blog post approved and published." : "Blog post rejected."
            ) { _ in nav.pop() }
        }
    }
}
