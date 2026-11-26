import Observation
import SwiftUI

// MARK: - hub

/// The Explore tab: a grid of the academy's content (Android's ExploreScreen).
struct ExploreScreen: View {
    @Environment(Navigator.self) private var nav

    var body: some View {
        let tiles: [(String, String, Icon, Route)] = [
            ("Fatwa", "Questions answered by scholars", .fatwa, .fatwa),
            ("Blog", "Articles from our teachers", .blog, .blog),
            ("Library", "Books to read and download", .library, .library),
            ("Bookstore", "Order printed books", .bookstore, .bookstore),
            ("Announcements", "News and events", .announcement, .announcements),
            ("Teachers", "Meet our scholars", .people, .teachers),
        ]
        VStack(spacing: 0) {
            TabTopBar("Explore")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Learn, read and ask — the academy's knowledge in one place.")
                        .textStyle(Typo.bodyMedium)
                        .foregroundStyle(Scheme.onSurfaceVariant)
                        .padding(.bottom, 4)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(tiles, id: \.0) { tile in
                            HubTile(title: tile.0, subtitle: tile.1, icon: tile.2) { nav.push(tile.3) }
                        }
                    }
                }
                .padding(Spacing.screen)
            }
        }
        .background(Scheme.background)
    }
}

private struct HubTile: View {
    let title: String
    let subtitle: String
    let icon: Icon
    let onClick: () -> Void

    var body: some View {
        AppCard(onClick: onClick) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle().fill(Scheme.primaryContainer)
                    icon.image.font(.system(size: 20, weight: .medium)).foregroundStyle(Scheme.onPrimaryContainer)
                }
                .frame(width: 46, height: 46)
                Spacer(minLength: 0)
                Text(title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface).lineLimit(1).minimumScaleFactor(0.8)
                Text(subtitle).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(height: 150 - 2 * Spacing.card, alignment: .topLeading)
        }
    }
}

// MARK: - blog

struct BlogListScreen: View {
    @Environment(Navigator.self) private var nav

    var body: some View {
        DetailScaffold("Blog") {
            WithModel({ c in let repo = c.repo; return PagedListModel<BlogPost> { p, q, _ in await repo.blog(page: p, search: q) } }) { model in
                PagedListBody(model, searchHint: "Search articles", emptyTitle: "No articles yet", key: \.id) { post in
                    BlogPostRow(post: post) { nav.push(.blogPost(id: post.id)) }
                }
            }
        }
    }
}

/// A blog post with its likes and comments (Android's BlogPostViewModel + PostState).
@MainActor
@Observable
final class BlogPostModel {
    private(set) var post: Load<BlogPost> = .loading
    private(set) var comments: [Comment] = []
    private(set) var busy = false
    private(set) var error: String?

    @ObservationIgnored private let repo: AcademyRepository
    @ObservationIgnored private let id: String
    @ObservationIgnored private var liking = false
    @ObservationIgnored private var loadedFor: String?

    init(repo: AcademyRepository, auth: AuthRepository, id: String) {
        self.repo = repo
        self.id = id
        loadedFor = auth.sessionStore.current?.user.id
        load()
        // "Liked by me" and comment rights depend on who is signed in: reload when that changes.
        auth.sessionStore.observe(owner: self) { [weak self] value in
            Task { @MainActor in self?.sessionChanged(value?.user.id) }
        }
    }

    private func sessionChanged(_ userId: String?) {
        guard userId != loadedFor else { return }
        loadedFor = userId
        load()
    }

    func load() {
        let repo = self.repo, id = self.id
        Task {
            let r = await repo.blogPost(id)
            if r.error?.cancelled == true { return }
            post = r.toLoad()
            if let value = r.value { comments = value.comments }
        }
    }

    /// A toggle: a second tap while the first is on its way would undo it, so it is ignored.
    func like() {
        if liking { return }
        guard let current = post.value else { return }
        liking = true
        let repo = self.repo, id = self.id
        Task {
            defer { liking = false }
            switch await repo.toggleLike(id) {
            case .success(let r):
                var updated = current
                updated.likedByMe = r.liked
                updated.likeCount = r.likeCount
                post = .ready(updated)
            case .failure(let e):
                error = e.message
            }
        }
    }

    /// A second tap before the first comment is posted is ignored: it would post it twice.
    func comment(_ text: String, onDone: @escaping () -> Void) {
        if busy { return }
        busy = true
        error = nil
        let repo = self.repo, id = self.id
        Task {
            switch await repo.addComment(id, content: text) {
            case .success(let c):
                busy = false
                comments = [c] + comments
                onDone()
            case .failure(let e):
                busy = false
                error = e.message
            }
        }
    }

    func delete(_ commentId: String) {
        let repo = self.repo
        Task {
            if await repo.deleteComment(commentId).isOk { comments.removeAll { $0.id == commentId } }
        }
    }

    func loadMore() {
        let repo = self.repo, id = self.id
        let skip = comments.count
        Task {
            if let more = await repo.blogComments(id, skip: skip).value {
                let known = Set(comments.map(\.id))
                comments += more.filter { !known.contains($0.id) }
            }
        }
    }
}

struct BlogPostScreen: View {
    let id: String

    var body: some View {
        DetailScaffold("") {
            WithModel({ BlogPostModel(repo: $0.repo, auth: $0.auth, id: id) }) { model in
                BlogPostContent(model: model)
            }
        }
    }
}

private struct BlogPostContent: View {
    let model: BlogPostModel
    @Environment(AppContainer.self) private var container
    @Environment(Navigator.self) private var nav
    @State private var draft = ""

    var body: some View {
        LoadContent(state: model.post, onRetry: { model.load() }) { post in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header(post)
                    // A post can repeat an image.
                    ForEach(Array(post.images.enumerated()), id: \.offset) { _, image in
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear
                                .aspectRatio(1.5, contentMode: .fit)
                                .overlay { RemoteImage(path: image.imagePath, contentDescription: image.caption) }
                                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            if let caption = image.caption {
                                Text(caption).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 8)
                    }
                    article(post)
                    commentsHeader
                    ForEach(model.comments) { c in commentRow(c) }
                    if model.comments.count < post.commentCount {
                        TextButton("Load more comments") { model.loadMore() }.padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func header(_ post: BlogPost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(post.title).textStyle(Typo.headlineMedium).foregroundStyle(Scheme.onSurface)
            Spacer().frame(height: 10)
            GoldRule()
            Spacer().frame(height: 10)
            Text([post.createdBy?.name, formatDate(post.createdAt)].compactMap { $0 }.joined(separator: " · "))
                .textStyle(Typo.labelMedium).foregroundStyle(Brand.gold)
        }
        .padding(.horizontal, 20)
    }

    private func article(_ post: BlogPost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let excerpt = post.excerpt, !excerpt.trimmed.isEmpty {
                Text(plainText(excerpt)).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurfaceVariant)
                Spacer().frame(height: 12)
            }
            HtmlText(html: post.body, serif: true)
            Spacer().frame(height: 16)
            HStack(spacing: 0) {
                IconButton(
                    post.likedByMe ? .heartFilled : .heart, label: "Like",
                    tint: post.likedByMe ? Brand.danger : Scheme.onSurfaceVariant
                ) {
                    if container.session == nil { nav.push(.signIn) } else { model.like() }
                }
                Text("\(post.likeCount)").textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurface)
                Spacer().frame(width: 16)
                Text(countOf(max(post.commentCount, model.comments.count), "comment"))
                    .textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurfaceVariant)
            }
        }
        .padding(20)
    }

    private var commentsHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Comments").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
            Spacer().frame(height: 10)
            if let error = model.error {
                Banner(error, tone: .danger)
                Spacer().frame(height: 8)
            }
            if container.session == nil {
                SecondaryButton("Sign in to comment") { nav.push(.signIn) }
            } else {
                CommentField(text: $draft, canPost: !draft.trimmed.isEmpty && !model.busy) {
                    model.comment(draft.trimmed) { draft = "" }
                }
            }
            Spacer().frame(height: 8)
        }
        .padding(.horizontal, 20)
    }

    private func commentRow(_ c: Comment) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Avatar(name: c.user?.name, image: c.user?.image, size: 36)
            Spacer().frame(width: 12)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(c.user?.name ?? "Student").textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                    Text(relativeTime(c.createdAt)).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                Text(c.content).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let mine = c.user?.id, mine == container.session?.user.id {
                IconButton(.delete, label: "Delete comment", tint: Scheme.onSurfaceVariant) { model.delete(c.id) }
                    .padding(.top, -6)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }
}

/// Material's OutlinedTextField with a placeholder and a Send button at its end (the blog's comment box).
private struct CommentField: View {
    @Binding var text: String
    let canPost: Bool
    let onPost: () -> Void
    @FocusState private var focused: Bool
    @State private var shown: String? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xs)
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Write a comment").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurfaceVariant).allowsHitTesting(false)
                }
                TextField("", text: Binding(get: { text }, set: { text = $0.jsPrefix(2000) }).shown($shown), axis: .vertical)
                    .correctsRefusedEdits(text: text, shown: $shown)
                    .lineLimit(1...5)
                    .textStyle(Typo.bodyLarge)
                    .foregroundStyle(Scheme.onSurface)
                    .tint(Scheme.primary)
                    .focused($focused)
                    .accessibilityLabel("Write a comment")
            }
            .padding(.leading, 16).padding(.vertical, 14)
            IconButton(.send, label: "Post", tint: canPost ? Scheme.onSurfaceVariant : Scheme.onSurface.opacity(0.38), action: onPost)
                .disabled(!canPost)
                .padding(.trailing, 4)
        }
        .frame(minHeight: 56)
        .overlay(shape.strokeBorder(focused ? Scheme.primary : Scheme.outline, lineWidth: focused ? 2 : 1))
        .contentShape(shape)
        .onTapGesture { focused = true }
    }
}

// MARK: - fatwa

struct FatwaListScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(Navigator.self) private var nav

    var body: some View {
        let categories = container.config?.lookups.fatwaCategories ?? []
        DetailScaffold("Fatwa") {
            WithModel({ c in let repo = c.repo; return PagedListModel<Fatwa> { p, q, f in await repo.fatwas(page: p, search: q, category: f) } }) { model in
                ZStack(alignment: .bottomTrailing) {
                    PagedListBody(model, searchHint: "Search questions", emptyTitle: "No answered questions yet", key: \.id) {
                        if !categories.isEmpty {
                            ChipRow(options: [(nil, "All")] + categories.map { ($0, $0) }, selected: model.state.filter) { model.filter($0) }
                        }
                    } row: { fatwa in
                        FatwaSummaryRow(fatwa: fatwa) { nav.push(.fatwaDetail(id: fatwa.id)) }
                    }
                    ExtendedFab(text: "Ask a question", icon: .edit) { nav.push(.askFatwa) }
                        .padding(16)
                }
            }
        }
    }
}

/// Material 3's ExtendedFloatingActionButton: a 56pt rounded box in the primary container colour, icon and label.
private struct ExtendedFab: View {
    let text: String
    let icon: Icon
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                icon.image.font(.system(size: 18, weight: .medium))
                Text(text).textStyle(Typo.labelLarge)
            }
            .foregroundStyle(Scheme.onPrimaryContainer)
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Scheme.primaryContainer, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle(shape: shape))
        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
    }
}

struct FatwaDetailScreen: View {
    let id: String

    var body: some View {
        DetailScaffold("Fatwa") {
            WithModel({ c in let repo = c.repo, id = id; return Loader<Fatwa> { await repo.fatwa(id) } }) { loader in
                LoadContent(state: loader.state, onRetry: { loader.load() }) { f in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Overline(text: f.category)
                            Spacer().frame(height: 6)
                            Text(f.title).textStyle(Typo.headlineSmall).foregroundStyle(Scheme.onSurface)
                            Spacer().frame(height: 16)
                            AppCard(color: Scheme.surfaceContainer) {
                                Overline(text: "Question", color: Scheme.onSurfaceVariant)
                                Spacer().frame(height: 6)
                                Text(f.question).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                                if let asker = f.askerName, !asker.trimmed.isEmpty, asker != anonymousAsker {
                                    Spacer().frame(height: 8)
                                    Text("Asked by \(asker)").textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurfaceVariant)
                                }
                            }
                            Spacer().frame(height: 20)
                            HStack(spacing: 8) {
                                Icon.mosque.image.font(.system(size: 17)).foregroundStyle(Brand.gold).frame(width: 20, height: 20)
                                Text("Answer").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                            }
                            Spacer().frame(height: 4)
                            if let answered = f.answeredAt {
                                Text(formatDate(answered)).textStyle(Typo.labelMedium).foregroundStyle(Brand.gold)
                            }
                            Spacer().frame(height: 12)
                            HtmlText(html: f.answer ?? "", serif: true)
                        }
                        .padding(Spacing.screen)
                    }
                    .refreshable { await loader.refresh() }
                }
            }
        }
    }
}

// MARK: - library

/// The website's topics (services/library-options.ts LIBRARY_TOPICS), the filter the library page offers.
let libraryTopics = ["Islam", "Quran", "Hadith", "Fiqh", "Tajweed", "Seerah", "Arabic Language", "Atheism", "Fatwa", "Qiraat", "Other"]

/// The website's empty-library line, which names the picked topic.
func libraryEmptyText(_ topic: String?) -> String {
    if let topic { return "No materials in \u{201C}\(topic)\u{201D} yet." }
    return "No library items available yet."
}

struct LibraryListScreen: View {
    @Environment(Navigator.self) private var nav

    var body: some View {
        DetailScaffold("Digital Library") {
            WithModel({ c in let repo = c.repo; return PagedListModel<LibraryItem> { p, q, t in await repo.library(page: p, search: q, topic: t) } }) { model in
                PagedListBody(model, searchHint: "Search books and materials...", emptyTitle: libraryEmptyText(model.state.filter), key: \.id) {
                    ChipRow(options: [(nil, "All")] + libraryTopics.map { ($0, $0) }, selected: model.state.filter) { model.filter($0) }
                } row: { item in
                    LibraryRow(item: item) { nav.push(.libraryItem(id: item.id)) }
                }
            }
        }
    }
}

private struct LibraryRow: View {
    let item: LibraryItem
    let onClick: () -> Void

    var body: some View {
        AppCard(padding: 12, onClick: onClick) {
            HStack(alignment: .top, spacing: 0) {
                RemoteImage(path: item.imagePath, contentDescription: item.title)
                    .frame(width: 64, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
                Spacer().frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Overline(text: item.topic)
                    Text(item.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface).lineLimit(2)
                    Text(item.author).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    Spacer().frame(height: 4)
                    Text([item.level, item.language].filter { !$0.trimmed.isEmpty }.joined(separator: " · "))
                        .textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                if item.pdfUrl != nil {
                    Icon.pdf.image.font(.system(size: 20)).foregroundStyle(Brand.gold).accessibilityLabel("PDF available")
                }
            }
        }
    }
}

struct LibraryItemScreen: View {
    let id: String

    var body: some View {
        DetailScaffold("Library") {
            WithModel({ c in let repo = c.repo, id = id; return Loader<LibraryItem> { await repo.libraryItem(id) } }) { loader in
                LoadContent(state: loader.state, onRetry: { loader.load() }) { item in
                    ScrollView {
                        VStack(spacing: 0) {
                            Color.clear
                                .aspectRatio(0.72, contentMode: .fit)
                                .overlay { RemoteImage(path: item.imagePath, contentDescription: item.title) }
                                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                                .frame(width: 180)
                            Spacer().frame(height: 20)
                            Overline(text: item.topic)
                            Text(item.title).textStyle(Typo.headlineSmall).foregroundStyle(Scheme.onSurface)
                            Text(item.author).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurfaceVariant)
                            Spacer().frame(height: 16)
                            AppCard {
                                DetailLine(label: "Level", value: item.level)
                                DetailLine(label: "Language", value: item.language)
                            }
                            Spacer().frame(height: 20)
                            if let pdf = item.pdfUrl {
                                PrimaryButton("View / download PDF") { openWeb(pdf) }
                            } else {
                                Banner("The PDF for this item is not available yet.", tone: .info, icon: .library)
                            }
                        }
                        .padding(Spacing.screen)
                    }
                }
            }
        }
    }
}

private struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        if !value.trimmed.isEmpty {
            HStack {
                Text(label).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant).frame(maxWidth: .infinity, alignment: .leading)
                Text(value).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
            }
            .padding(.vertical, 6)
        }
    }
}

// MARK: - announcements

struct AnnouncementsScreen: View {
    @Environment(Navigator.self) private var nav

    var body: some View {
        DetailScaffold("Announcements") {
            WithModel({ c in let repo = c.repo; return PagedListModel<SiteAnnouncement> { p, q, _ in await repo.announcements(page: p, search: q) } }) { model in
                PagedListBody(model, searchHint: nil, emptyTitle: "No announcements", key: \.id) { a in
                    AppCard(padding: 0, onClick: { nav.push(.announcement(id: a.id)) }) {
                        if let image = a.images.first {
                            RemoteImage(path: image.imagePath).frame(maxWidth: .infinity).frame(height: 150)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Overline(text: formatDate(a.eventDate ?? a.createdAt))
                            Spacer().frame(height: 4)
                            Text(a.title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                            Spacer().frame(height: 4)
                            Text(plainText(a.body)).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(3)
                        }
                        .multilineTextAlignment(.leading)
                        .padding(16)
                    }
                }
            }
        }
    }
}

struct AnnouncementScreen: View {
    let id: String

    var body: some View {
        DetailScaffold("Announcement") {
            WithModel({ c in let repo = c.repo, id = id; return Loader<SiteAnnouncement> { await repo.announcement(id) } }) { loader in
                LoadContent(state: loader.state, onRetry: { loader.load() }) { a in
                    ScreenColumn(spacing: 12) {
                        Text(a.title).textStyle(Typo.headlineSmall).foregroundStyle(Scheme.onSurface)
                        GoldRule()
                        if a.eventDate != nil || a.location != nil {
                            AppCard(color: Scheme.secondaryContainer.opacity(0.5)) {
                                if let date = a.eventDate {
                                    Text("📅  \(formatDate(date))").textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                                }
                                if let location = a.location {
                                    HStack(spacing: 6) {
                                        Icon.location.image.font(.system(size: 13)).foregroundStyle(Brand.gold).frame(width: 16, height: 16)
                                        Text(location).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                                    }
                                }
                            }
                        }
                        ForEach(Array(a.images.enumerated()), id: \.offset) { _, image in
                            Color.clear
                                .aspectRatio(1.5, contentMode: .fit)
                                .overlay { RemoteImage(path: image.imagePath, contentDescription: image.caption) }
                                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        }
                        HtmlText(html: a.body)
                        Text("Posted \(formatDate(a.createdAt))").textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

// MARK: - teachers

struct TeachersScreen: View {
    @Environment(Navigator.self) private var nav

    var body: some View {
        DetailScaffold("Our teachers") {
            WithModel({ c in let repo = c.repo; return PagedListModel<Teacher> { p, q, _ in await repo.teachers(page: p, search: q) } }) { model in
                PagedListBody(model, searchHint: "Search teachers", emptyTitle: "No teachers listed", key: \.id) { t in
                    AppCard(onClick: { nav.push(.teacher(id: t.id)) }) {
                        HStack(spacing: 0) {
                            Avatar(name: t.name, image: t.imageUrl, size: 56)
                            Spacer().frame(width: 14)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(t.name).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                                Text(t.specialization).textStyle(Typo.bodySmall).foregroundStyle(Brand.gold)
                                Spacer().frame(height: 4)
                                Text(t.bio).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(2)
                            }
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

struct TeacherScreen: View {
    let id: String
    @Environment(Navigator.self) private var nav

    var body: some View {
        DetailScaffold("") {
            WithModel({ c in let repo = c.repo, id = id; return Loader<TeacherDetailResponse> { await repo.teacher(id) } }) { loader in
                LoadContent(state: loader.state, onRetry: { loader.load() }) { d in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            VStack(spacing: 0) {
                                Avatar(name: d.teacher.name, image: d.teacher.imageUrl, size: 96)
                                Spacer().frame(height: 12)
                                Text(d.teacher.name).textStyle(Typo.headlineSmall).foregroundStyle(Scheme.onSurface)
                                Text(d.teacher.specialization).textStyle(Typo.bodyMedium).foregroundStyle(Brand.gold)
                                Spacer().frame(height: 14)
                                Text(d.teacher.bio).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                            }
                            .frame(maxWidth: .infinity)
                            if !d.courses.isEmpty {
                                Text("Courses").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface).padding(.top, 8)
                                ForEach(d.courses) { course in
                                    TeacherCourseCard(course: course) { nav.push(.course(id: course.id)) }
                                }
                            }
                        }
                        .padding(Spacing.screen)
                    }
                }
            }
        }
    }
}

/// A course on a teacher's page: Explore's copy of Android's CourseCard (ui/courses, owned by the Courses area).
private struct TeacherCourseCard: View {
    let course: Course
    let onClick: () -> Void

    var body: some View {
        AppCard(padding: 0, onClick: onClick) {
            HeroBox {
                HStack {
                    Overline(text: course.category.trimmed.isEmpty ? "Course" : course.category, color: Brand.goldSoft)
                    Spacer()
                    if !course.level.trimmed.isEmpty {
                        Text(course.level).textStyle(Typo.labelMedium).foregroundStyle(Brand.mint)
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 70)
            VStack(alignment: .leading, spacing: 0) {
                Text(course.title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                Spacer().frame(height: 6)
                Text(plainText(course.description)).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(2)
                if let teacher = course.teacher {
                    Spacer().frame(height: 12)
                    HStack(spacing: 10) {
                        Avatar(name: teacher.name, image: teacher.imageUrl, size: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(teacher.name).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                            Text(teacher.specialization).textStyle(Typo.bodySmall).foregroundStyle(Brand.gold).lineLimit(1)
                        }
                    }
                }
                Spacer().frame(height: 12)
                WeightedRow(weights: [1, 1.4]) {
                    FeeBlock(label: "Enrollment", value: course.priceInrPaise > 0 ? rupees(course.priceInrPaise) : "Free")
                    FeeBlock(label: "Course fee", value: courseFeeText(course))
                }
            }
            .multilineTextAlignment(.leading)
            .padding(16)
        }
    }
}

private struct FeeBlock: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
            Text(value).textStyle(Typo.titleMedium).foregroundStyle(Scheme.primary)
        }
    }
}

