import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/content/Fatwa.kt.

/// Whose fatwa screens these are: the admin's, or a teacher's assigned questions (Android's FatwaAudience).
enum FatwaAudience: Hashable, Sendable { case admin, teacher }

// Android's FatwaListScreen; renamed because the student app's fatwa list already has that name.

struct ManageFatwaListScreen: View {
    let audience: FatwaAudience

    var body: some View { StubScreen(title: "Fatwa Q&A") }
}

struct FatwaAnswerScreen: View {
    let audience: FatwaAudience
    let id: String

    var body: some View { StubScreen(title: "Fatwa question") }
}
