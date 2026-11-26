import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/bookstore/BooksAdmin.kt.

struct BooksListScreen: View {
    var body: some View { StubScreen(title: "Bookstore") }
}

struct BookDetailScreen: View {
    let id: String

    var body: some View { StubScreen(title: "Book details") }
}

struct BookFormScreen: View {
    let id: String?

    var body: some View { StubScreen(title: id == nil ? "Add book" : "Edit book") }
}
