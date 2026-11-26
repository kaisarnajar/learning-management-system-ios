import SwiftUI

/*
 * Content management: site announcements, blogs and blog approvals, fatwa Q&A, the digital library and the verse &
 * hadith of the day (/api/v1/admin/...), and the teacher's own blog posts and fatwa answers (/api/v1/teacher/...).
 * Writes run the website's server actions, so their bodies are the website forms' fields. Ported from Android's
 * ui/manage/content/ContentTones.kt.
 */

/// Chip colours matching the website's badges.
func contentTone(_ label: String) -> Tone {
    switch label {
    case "Published", "Answered": .success
    case "Home + Public", "On homepage", "Approved": .info
    case "Pending approval", "Pending Review": .warning
    case "Rejected": .danger
    default: .neutral
    }
}
