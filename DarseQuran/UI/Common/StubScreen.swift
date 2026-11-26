import SwiftUI

/// A screen that hasn't been built yet: a top bar and an empty state. Replaced screen by screen.
struct StubScreen: View {
    let title: String
    var tab: Bool = false

    var body: some View {
        if tab {
            VStack(spacing: 0) { TabTopBar(title); EmptyState(title: title, message: "Coming soon."); Spacer() }
                .background(Scheme.background.ignoresSafeArea())
        } else {
            DetailScaffold(title) { EmptyState(title: title, message: "Coming soon.") }
        }
    }
}
