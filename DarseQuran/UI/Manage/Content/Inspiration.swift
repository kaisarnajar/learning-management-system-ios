import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/content/Inspiration.kt.

struct InspirationListScreen: View {
    var body: some View { StubScreen(title: "Verse & Hadith") }
}

struct InspirationDetailScreen: View {
    let id: String

    var body: some View { StubScreen(title: "Verse & Hadith") }
}

struct InspirationFormScreen: View {
    let id: String?

    var body: some View { StubScreen(title: id == nil ? "New verse or hadith" : "Edit verse or hadith") }
}
