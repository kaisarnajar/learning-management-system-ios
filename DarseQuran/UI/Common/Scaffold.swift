import SwiftUI

/// A detail screen: the back top bar, then [content] filling the rest (Android's Scaffold + BackTopBar, and the staff
/// screens' ManageScaffold). Back pops the current tab's stack, or calls [onBack] when given (sheets).
struct DetailScaffold<Actions: View, Content: View>: View {
    let title: String
    var onBack: (() -> Void)? = nil
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content
    @Environment(Navigator.self) private var nav: Navigator?
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, onBack: (() -> Void)? = nil, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.onBack = onBack
        self.actions = actions
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            BackTopBar(title, onBack: back, actions: actions)
            content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Scheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func back() {
        if let onBack { onBack() } else if let nav, !nav.currentPath.isEmpty { nav.pop() } else { dismiss() }
    }
}

/// A scrolling column with the screen padding (20pt) and the given spacing: the body of most forms and detail pages.
struct ScreenColumn<Content: View>: View {
    var spacing: CGFloat = 12
    var padding: CGFloat = Spacing.screen
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// A bar pinned to the bottom of a screen above the content (course detail's action bar, pay's continue button).
struct StickyBottomBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HairlineDivider()
            content()
                .padding(.horizontal, Spacing.screen)
                .padding(.vertical, 12)
        }
        .background(Scheme.surfaceContainerLowest.ignoresSafeArea(edges: .bottom))
        .shadow(color: Brand.cardShadow, radius: 6, x: 0, y: -2)
    }
}

/// Material's AlertDialog with a confirm and a dismiss button, for destructive or important confirmations.
extension View {
    func confirmDialog(_ title: String, message: String, isPresented: Binding<Bool>, confirm: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        alert(title, isPresented: isPresented) {
            Button("Cancel", role: .cancel) {}
            Button(confirm, role: destructive ? .destructive : nil, action: action)
        } message: {
            Text(message)
        }
    }
}
