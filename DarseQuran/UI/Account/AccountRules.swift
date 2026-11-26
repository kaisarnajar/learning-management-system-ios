import Foundation

// Android's NotificationLinks.kt, ProfileRules.kt and ResendState.kt.

// MARK: - notification links

/// The website's label for where a notification leads (app/profile/notifications/[id]/page.tsx relatedPageLabel); nil
/// when it leads nowhere but the notifications list.
func relatedPageLabel(_ href: String) -> String? {
    var path = href.components(separatedBy: "?").first ?? ""
    if let origin = path.firstMatch(of: /^https?:\/\/[^\/]+/) { path.removeSubrange(origin.range) }
    if path.isEmpty || path == "/profile/notifications" { return nil }
    if path.hasPrefix("/profile/payments") { return "View in Payments" }
    if path.contains("/announcements") { return "View announcement" }
    if path.hasPrefix("/profile/courses") { return "View in My Courses" }
    if path.hasPrefix("/profile/cart") || path.hasPrefix("/bookstore") { return "View order" }
    if path.hasPrefix("/blog/") { return "View blog post" }
    return "View related page"
}

// MARK: - profile

/// The website takes a profile photo only from men (ProfileForm.tsx disables it unless gender is MALE).
func photoAllowed(_ gender: String?) -> Bool { gender == "MALE" }

/// The website's hint next to "Profile Photo".
func photoHint(_ gender: String?) -> String {
    switch gender {
    case "FEMALE": "Profile Photo (Disabled for Female)"
    case "MALE": "Profile Photo (Optional)"
    default: "Profile Photo (Select gender first)"
    }
}

/// True when this save is the one that completed the profile, so the "profile is complete" step is due.
func profileJustCompleted(wasComplete: Bool, isComplete: Bool) -> Bool { !wasComplete && isComplete }

let profileCompleteTitle = "Your profile is complete"
let profileCompleteText = "You can browse courses and request enrollment. Any enrollment or monthly fees are shown on each course."
let profileIncompleteTitle = "Complete your profile to enroll in courses"
let profileIncompleteText = "The academy needs your full details for course registration. Fill in all fields below, then return to " +
    "the course page to request enrollment."

// MARK: - verification resend

/// The website's VerificationBanner states: idle, sending, or the answer to the last resend.
struct ResendState: Equatable {
    var sending = false
    var sent = false
    var message: String? = nil
}

let verificationSent = "Verification email sent! Please check your Inbox. If you don't see it, check your Spam/Junk folder as well."

/// The state after a resend answered with [result].
func resendOutcome<T>(_ result: ApiResult<T>) -> ResendState {
    switch result {
    case .success: ResendState(sent: true, message: verificationSent)
    case .failure(let e): ResendState(message: e.message.trimmed.isEmpty ? "Failed to resend verification email." : e.message)
    }
}

/// The button's words, as on the website.
func resendLabel(_ state: ResendState) -> String {
    if state.sending { return "Sending..." }
    if state.sent { return "Sent" }
    return "Resend Verification Email"
}
