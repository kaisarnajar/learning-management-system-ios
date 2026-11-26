import Observation
import SwiftUI

/*
 * Building blocks of the admin and teacher screens (Android's ui/manage/common/ManageKit.kt). A typical section is:
 *
 *   list   — ManageListScreen + a PagedListModel(app:) { app, page, q, filter in try await app.service(XAPI.self).list(…) }
 *   detail — ManageScaffold + a Loader(app:) { try await $0.service(XAPI.self).get(id) } + LoadedColumn +
 *            DetailCard / Field + ActionRunner
 *   form   — FormScreen (Forms.swift) + fields, saving through ActionRunner
 *
 * Screens keep their state in a `@MainActor @Observable` model built once with `WithModel` (Android's ViewModel):
 *
 *     @MainActor @Observable final class StudentDetailModel {
 *         let loader: Loader<StudentResponse>
 *         let runner: ActionRunner
 *         init(app: AppContainer, id: String) {
 *             loader = Loader(app: app) { try await $0.service(StudentsAdminAPI.self).get(id) }
 *             runner = ActionRunner(app: app)
 *         }
 *     }
 *     struct StudentDetailScreen: View {
 *         let id: String
 *         var body: some View { WithModel({ StudentDetailModel(app: $0, id: id) }) { StudentDetailContent(model: $0) } }
 *     }
 *
 * Navigation: Android hands screens callbacks (onBack, onOpen, …); here a screen reads the Navigator from the
 * environment and pushes `.manage(...)` routes itself (`nav.push(.manage(.studentAdmin(id: id)))`, `nav.pop()`).
 * Android's snackbars are the app's toasts (`ActionRunner.message`, `Toaster`).
 */

// MARK: - data

/// `apiCall` for blocks that run on the main actor (the kit's loaders and actions, which reach the AppContainer):
/// HTTP and network failures become an [ApiError] with the server's message.
@MainActor
func mainApiCall<T>(_ block: @MainActor () async throws -> T) async -> ApiResult<T> {
    do {
        return .success(try await block())
    } catch {
        return .failure(apiError(from: error))
    }
}

extension Loader {
    /// A loader whose [fetch] runs through `apiCall` (Android's `rememberLoader(key) { service<XApi>().get(id) }`).
    /// Build it inside a screen model created by `WithModel`, so it lives as long as the screen.
    convenience init(app: AppContainer, _ fetch: @escaping @MainActor (AppContainer) async throws -> T) {
        self.init { await mainApiCall { try await fetch(app) } }
    }
}

extension PagedListModel {
    /// A searchable, filterable, paged list whose `fetch(app, page, query, filter)` returns the API's `Paged` body,
    /// run through `apiCall` (Android's `rememberPaged(key) { page, q, filter -> … }`).
    convenience init(
        app: AppContainer, filter: String? = nil,
        _ fetch: @escaping @MainActor (_ app: AppContainer, _ page: Int, _ query: String, _ filter: String?) async throws -> Paged<T>
    ) {
        self.init(filter: filter) { page, query, filter in await mainApiCall { try await fetch(app, page, query, filter) } }
    }
}

// MARK: - actions

/// Runs writes from a screen: one at a time ([busy]), errors and confirmations as toasts (Android's snackbars).
///
///     runner.run({ try await $0.service(StudentsAdminAPI.self).delete(id) }, success: "Deleted.") { _ in nav.pop() }
///
/// [busy] is set before the write starts, so a second tap in the same frame is ignored rather than sending the write
/// twice. The write is not tied to the screen: it finishes, and its message shows, even if the screen is closed
/// meanwhile (Android keeps the runner in a ViewModel for the same reason).
@MainActor
@Observable
final class ActionRunner {
    private(set) var busy = false
    @ObservationIgnored private let app: AppContainer
    @ObservationIgnored private let toaster: Toaster

    init(app: AppContainer) {
        self.app = app
        self.toaster = app.toaster
    }

    /// Runs [block] unless a write is already running; on success calls [onSuccess] and shows [success], on failure
    /// shows the server's message.
    func run<T>(_ block: @escaping @MainActor (AppContainer) async throws -> T, success: String? = nil, onSuccess: @escaping @MainActor (T) -> Void = { _ in }) {
        if busy { return }
        busy = true
        let app = self.app
        Task {
            let result = await mainApiCall { try await block(app) }
            self.busy = false
            switch result {
            case .success(let value):
                onSuccess(value)
                if let success { self.message(success) }
            case .failure(let error):
                if !error.cancelled { self.message(error.message) }
            }
        }
    }

    /// Shows [text] at the bottom of the screen.
    func message(_ text: String) { toaster.show(text) }

    /// Downloads a PDF (or other file) with [fetch] (an API download, e.g. `$0.service(MoneyAPI.self).receiptPdf(id,
    /// fileName: name)`) and opens it in the document viewer (QuickLook: preview, share, save to Files).
    func openFile(_ fetch: @escaping @MainActor (AppContainer) async throws -> URL) {
        run(fetch) { file in DocumentPreview.open(file) }
    }
}

// MARK: - layout

/// The frame of every admin and teacher screen: a plain top bar (back arrow on pushed screens, centred title on tabs),
/// an optional floating action and an optional bar pinned to the bottom (Android's ManageScaffold). Back pops the
/// tab's stack, or calls [onBack] when given (a sheet).
struct ManageScaffold<Actions: View, Fab: View, Bottom: View, Content: View>: View {
    let title: String
    var tab: Bool = false
    var onBack: (() -> Void)? = nil
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var fab: () -> Fab
    @ViewBuilder var bottomBar: () -> Bottom
    @ViewBuilder var content: () -> Content

    init(
        _ title: String, tab: Bool = false, onBack: (() -> Void)? = nil,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() },
        @ViewBuilder fab: @escaping () -> Fab = { EmptyView() },
        @ViewBuilder bottomBar: @escaping () -> Bottom = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.tab = tab
        self.onBack = onBack
        self.actions = actions
        self.fab = fab
        self.bottomBar = bottomBar
        self.content = content
    }

    var body: some View {
        if tab {
            VStack(spacing: 0) {
                TabTopBar(title, actions: actions)
                frame
            }
            .background(Scheme.background.ignoresSafeArea())
        } else {
            DetailScaffold(title, onBack: onBack, actions: actions) { frame }
        }
    }

    private var frame: some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .bottomTrailing) { fab().padding(16) }
            bottomBar()
        }
    }
}

/// "+ New …" floating button (Material's ExtendedFloatingActionButton in the primary colour).
struct AddFab: View {
    let label: String
    var icon: Icon = .add
    let action: () -> Void

    init(_ label: String, icon: Icon = .add, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                icon.image.font(.system(size: 20, weight: .medium))
                Text(label).textStyle(Typo.labelLarge)
            }
            .foregroundStyle(Scheme.onPrimary)
            .padding(.leading, 16).padding(.trailing, 20)
            .frame(height: 56)
            .background(Scheme.primary, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle(shape: shape))
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        .accessibilityLabel(label)
    }
}

/// A filter: [value] nil means "all".
struct FilterOption: Hashable, Sendable {
    let value: String?
    let label: String

    init(_ value: String?, _ label: String) {
        self.value = value
        self.label = label
    }
}

/// A row of filter chips that scrolls sideways; the selected one is filled (Android's FilterChips).
struct FilterChips: View {
    let options: [FilterOption]
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    FilterChip(label: option.label, selected: option.value == selected) { onSelect(option.value) }
                }
            }
        }
    }
}

/// A full list screen: search, optional filter chips, pull to refresh, infinite scroll, empty and error states
/// (Android's ManageListScreen). Pass `tab: true` when the list is a tab's first screen.
struct ManageListScreen<T: Model, K: Hashable, Actions: View, Fab: View, Header: View, Row: View>: View {
    let title: String
    var tab: Bool = false
    let model: PagedListModel<T>
    let key: (T) -> K
    let emptyTitle: String
    var searchHint: String? = "Search"
    var filters: [FilterOption] = []
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var fab: () -> Fab
    @ViewBuilder var header: () -> Header
    @ViewBuilder var row: (T) -> Row

    init(
        _ title: String, tab: Bool = false, model: PagedListModel<T>, key: @escaping (T) -> K, emptyTitle: String,
        searchHint: String? = "Search", filters: [FilterOption] = [],
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() },
        @ViewBuilder fab: @escaping () -> Fab = { EmptyView() },
        @ViewBuilder header: @escaping () -> Header = { EmptyView() },
        @ViewBuilder row: @escaping (T) -> Row
    ) {
        self.title = title
        self.tab = tab
        self.model = model
        self.key = key
        self.emptyTitle = emptyTitle
        self.searchHint = searchHint
        self.filters = filters
        self.actions = actions
        self.fab = fab
        self.header = header
        self.row = row
    }

    var body: some View {
        ManageScaffold(title, tab: tab, actions: actions, fab: fab) {
            PagedListBody(model, searchHint: searchHint, emptyTitle: emptyTitle, key: key, header: {
                if !filters.isEmpty { FilterChips(options: filters, selected: model.state.filter) { model.filter($0) } }
                header()
            }, row: row)
        }
    }
}

/// A screen body that loads one record and shows it in a scrolling column, with pull to refresh (Android's
/// LoadedColumn): 20pt sides, 8pt top, 96pt bottom (room for a floating button), 14pt between items.
struct LoadedColumn<T, Content: View>: View {
    let loader: Loader<T>
    var spacing: CGFloat = 14
    @ViewBuilder var content: (T) -> Content

    init(_ loader: Loader<T>, spacing: CGFloat = 14, @ViewBuilder content: @escaping (T) -> Content) {
        self.loader = loader
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        LoadContent(state: loader.state, onRetry: { loader.load() }) { value in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: spacing) { content(value) }
                    .padding(.horizontal, Spacing.screen)
                    .padding(.top, 8)
                    .padding(.bottom, 96)
            }
            .refreshable { await loader.refresh() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - content

/// One row of an admin list: title, up to two lines of detail, an optional chip and a leading picture or icon; a
/// chevron when it opens something (Android's RecordCard).
struct RecordCard<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var meta: String? = nil
    var chip: (String, Tone)? = nil
    var onClick: (() -> Void)? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String, subtitle: String? = nil, meta: String? = nil, chip: (String, Tone)? = nil, onClick: (() -> Void)? = nil,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.chip = chip
        self.onClick = onClick
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        AppCard(padding: 14, onClick: onClick) {
            HStack(alignment: .center, spacing: 0) {
                if Leading.self != EmptyView.self { leading(); Spacer().frame(width: 12) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface).lineLimit(2).multilineTextAlignment(.leading)
                    if let subtitle, !subtitle.trimmed.isEmpty {
                        Text(subtitle).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    if let meta, !meta.trimmed.isEmpty {
                        Text(meta).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(1)
                    }
                    if let chip {
                        Spacer().frame(height: 6)
                        StatusChip(chip.0, tone: chip.1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if Trailing.self != EmptyView.self {
                    trailing()
                } else if onClick != nil {
                    Icon.chevronRight.image.font(.system(size: 14, weight: .semibold)).foregroundStyle(Scheme.onSurfaceVariant)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// A titled card of label/value rows (`Field`) or any other content, 10pt apart (Android's DetailCard).
struct DetailCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        AppCard {
            if let title {
                Text(title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.primary).accessibilityAddTraits(.isHeader)
                Spacer().frame(height: 10)
            }
            VStack(alignment: .leading, spacing: 10) { content() }
        }
    }
}

/// A label above its value ("—" when blank); hidden when [value] is blank unless [showEmpty] (Android's Field).
struct Field: View {
    let label: String
    let value: String?
    var showEmpty: Bool = true

    init(_ label: String, _ value: String?, showEmpty: Bool = true) {
        self.label = label
        self.value = value
        self.showEmpty = showEmpty
    }

    var body: some View {
        let blank = value?.trimmed.isEmpty ?? true
        if !blank || showEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurfaceVariant)
                Text(blank ? "—" : value!).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Label on the left, value on the right: for amounts and short facts (Android's FieldRow).
struct FieldRow: View {
    let label: String
    let value: String?
    var strong: Bool = false

    init(_ label: String, _ value: String?, strong: Bool = false) {
        self.label = label
        self.value = value
        self.strong = strong
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(label).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant).frame(maxWidth: .infinity, alignment: .leading)
            Text(value ?? "—").textStyle(strong ? Typo.titleSmall : Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A 1pt rule in the soft outline colour (Android's Divider in ManageKit; named so it doesn't hide SwiftUI's Divider).
struct ManageDivider: View {
    var body: some View { Rectangle().fill(Brand.outlineSoft).frame(height: 1).frame(maxWidth: .infinity) }
}

/// A small count tile (dashboard and summaries); amber when [highlight].
struct StatTile: View {
    let label: String
    let value: String
    var highlight: Bool = false
    var onClick: (() -> Void)? = nil

    init(_ label: String, _ value: String, highlight: Bool = false, onClick: (() -> Void)? = nil) {
        self.label = label
        self.value = value
        self.highlight = highlight
        self.onClick = onClick
    }

    var body: some View {
        AppCard(padding: 14, color: highlight ? Brand.warningContainer : Scheme.surfaceContainerLowest, onClick: onClick) {
            Text(label).textStyle(Typo.labelMedium).foregroundStyle(highlight ? Brand.warning : Scheme.onSurfaceVariant).lineLimit(2)
            Spacer().frame(height: 4)
            Text(value).textStyle(Typo.headlineSmall).foregroundStyle(highlight ? Brand.warning : Scheme.onSurface)
        }
        .accessibilityElement(children: .combine)
    }
}

/// An inline error or note at the top of a screen; nothing when [text] is blank (Android's Notice).
struct Notice: View {
    let text: String?
    var tone: Tone = .danger

    init(_ text: String?, tone: Tone = .danger) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        if let text, !text.trimmed.isEmpty { Banner(text, tone: tone) }
    }
}

/// Small icon for list rows without a picture: 40pt circle in the primary container (Android's RowIcon).
struct RowIcon: View {
    let icon: Icon
    var tint: Color = Scheme.onPrimaryContainer

    init(_ icon: Icon, tint: Color = Scheme.onPrimaryContainer) {
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        ZStack {
            Circle().fill(Scheme.primaryContainer)
            icon.image.font(.system(size: 18, weight: .medium)).foregroundStyle(tint)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

// MARK: - dialogs

extension View {
    /// Ask before a destructive or important action about [item] (Android's `deleting?.let { ConfirmDialog(…) }`): shown
    /// while [item] is set; Cancel or confirming clears it. For a plain yes/no use `.confirmDialog(…)` (Scaffold.swift).
    func confirmDialog<Item>(
        item: Binding<Item?>, title: String, message: @escaping (Item) -> String, confirm: String, destructive: Bool = false,
        action: @escaping (Item) -> Void
    ) -> some View {
        let shown = Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
        let current = item.wrappedValue
        return alert(title, isPresented: shown, presenting: current) { value in
            Button("Cancel", role: .cancel) {}
            Button(confirm, role: destructive ? .destructive : nil) { action(value) }
        } message: { value in
            Text(message(value))
        }
    }

    /// Ask for a short text (a reason, a note) before an action (Android's TextInputDialog): a Material dialog with an
    /// optional [message], a text field ([singleLine], or three lines and more), Cancel and [confirmLabel]. [required]
    /// blocks an empty answer; the answer is trimmed.
    func textInputDialog(
        isPresented: Binding<Bool>, title: String, label: String, confirmLabel: String, initial: String = "",
        required: Bool = false, message: String? = nil, singleLine: Bool = false, destructive: Bool = false,
        onConfirm: @escaping (String) -> Void
    ) -> some View {
        materialDialog(isPresented: isPresented) {
            TextInputDialogBody(
                title: title, label: label, confirmLabel: confirmLabel, initial: initial, required: required, message: message,
                singleLine: singleLine, destructive: destructive, onConfirm: onConfirm, onDismiss: { isPresented.wrappedValue = false }
            )
        }
    }

    /// A Material dialog (Android's AlertDialog look: 16pt corners, the raised surface, a scrim) over the whole screen,
    /// for dialogs an iOS alert can't hold (several lines of text, a date picker). [content] is the dialog's body; it
    /// closes itself by setting [isPresented] to false.
    func materialDialog<Body: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Body) -> some View {
        fullScreenCover(isPresented: isPresented) {
            MaterialDialogFrame(onDismiss: { isPresented.wrappedValue = false }, content: content)
                .presentationBackground(.clear)
        }
    }
}

/// The scrim and the dialog card of [materialDialog].
private struct MaterialDialogFrame<Body: View>: View {
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Body
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.32 : 0).ignoresSafeArea().onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .background(Scheme.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
                .padding(.horizontal, 24)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.96)
                .accessibilityAddTraits(.isModal)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.18)) { shown = true } }
    }
}

/// The title of a Material dialog (headlineSmall).
struct DialogTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).textStyle(Typo.headlineSmall).foregroundStyle(Scheme.onSurface).accessibilityAddTraits(.isHeader)
            .padding(.bottom, 16)
    }
}

/// A Material dialog's buttons: text buttons at the end, 8pt apart.
struct DialogButtons: View {
    let dismissLabel: String
    let confirmLabel: String
    var confirmEnabled: Bool = true
    var destructive: Bool = false
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            BarTextButton(dismissLabel, action: onDismiss)
            BarTextButton(confirmLabel, enabled: confirmEnabled, color: destructive ? Scheme.error : Scheme.primary, action: onConfirm)
        }
        .padding(.top, 24)
    }
}

private struct TextInputDialogBody: View {
    let title: String
    let label: String
    let confirmLabel: String
    let initial: String
    let required: Bool
    let message: String?
    let singleLine: Bool
    let destructive: Bool
    let onConfirm: (String) -> Void
    let onDismiss: () -> Void
    @State private var value: String

    init(
        title: String, label: String, confirmLabel: String, initial: String, required: Bool, message: String?, singleLine: Bool,
        destructive: Bool, onConfirm: @escaping (String) -> Void, onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.label = label
        self.confirmLabel = confirmLabel
        self.initial = initial
        self.required = required
        self.message = message
        self.singleLine = singleLine
        self.destructive = destructive
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _value = State(initialValue: initial)
    }

    var body: some View {
        DialogTitle(title)
        VStack(alignment: .leading, spacing: 12) {
            if let message { Text(message).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant) }
            OutlinedField(label: label, text: $value, lines: singleLine ? nil : 3...8)
                .backgroundStyle(Scheme.surfaceContainerHigh)
                .environment(\.fieldSurface, Scheme.surfaceContainerHigh) // the floating label sits on the dialog
        }
        DialogButtons(
            dismissLabel: "Cancel", confirmLabel: confirmLabel, confirmEnabled: !required || !value.trimmed.isEmpty, destructive: destructive,
            onDismiss: onDismiss, onConfirm: { onDismiss(); onConfirm(value.trimmed) }
        )
    }
}

/// Material's TextButton with an enabled state (top-bar "Save", dialog buttons): primary label, 38% when disabled.
struct BarTextButton: View {
    let text: String
    var enabled: Bool = true
    var color: Color = Scheme.primary
    let action: () -> Void

    init(_ text: String, enabled: Bool = true, color: Color = Scheme.primary, action: @escaping () -> Void) {
        self.text = text
        self.enabled = enabled
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text).textStyle(Typo.labelLarge)
                .foregroundStyle(enabled ? color : Scheme.onSurface.opacity(0.38))
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(shape: Capsule()))
        .disabled(!enabled)
    }
}
