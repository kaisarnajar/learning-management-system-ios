import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/people/Reviews.kt.

struct ReviewsListScreen: View {
    var body: some View { StubScreen(title: "Reviews") }
}

struct ReviewDetailScreen: View {
    let id: String

    var body: some View { StubScreen(title: "Student review") }
}

struct ReviewEditScreen: View {
    let id: String

    var body: some View { StubScreen(title: "Edit review settings") }
}
