import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/content/Announcements.kt.

struct AnnouncementsListScreen: View {
    var body: some View { StubScreen(title: "Announcements") }
}

struct SiteAnnouncementFormScreen: View {
    let id: String?

    var body: some View { StubScreen(title: id == nil ? "New announcement" : "Edit announcement") }
}
