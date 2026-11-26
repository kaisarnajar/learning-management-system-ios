import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/content/Library.kt.

// ManageLibraryListScreen is Android's LibraryListScreen; renamed because the student app's library list has that name.

struct ManageLibraryListScreen: View {
    var body: some View { StubScreen(title: "Library") }
}

struct LibraryDetailScreen: View {
    let id: String

    var body: some View { StubScreen(title: "Library item") }
}

struct LibraryFormScreen: View {
    let id: String?

    var body: some View { StubScreen(title: id == nil ? "Add library item" : "Edit library item") }
}
