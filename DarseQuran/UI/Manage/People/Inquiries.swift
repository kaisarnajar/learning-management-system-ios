import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/people/Inquiries.kt.

struct InquiriesListScreen: View {
    var body: some View { StubScreen(title: "Contact inquiries") }
}

struct InquiryDetailScreen: View {
    let id: String

    var body: some View { StubScreen(title: "Contact inquiry") }
}

struct InquiryReplyScreen: View {
    let id: String

    var body: some View { StubScreen(title: "Reply to inquiry") }
}
