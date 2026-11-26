import Foundation

/// The website's studentReviewSchema limits (Android's ReviewRules.kt).
let reviewQuoteMin = 20
let reviewQuoteMax = 1000
let reviewFieldMax = 120
let reviewRatingMax = 5

/// Featured on the homepage at most this many at a time (HOMEPAGE_FEATURED_REVIEWS_MAX).
let homepageFeaturedReviewsMax = 4

let reviewRatingError = "Select a star rating from 1 to 5."

/// The review form's fields; the rating starts unchosen (0), as on the website.
struct ReviewDraft: Equatable {
    var rating = 0
    var quote = ""
    var course = ""
    var location = ""
}

/// Course and location are capped at [reviewFieldMax] as they are typed, as the website's inputs are.
enum ReviewField: Hashable { case rating, quote }

/// The website's messages for each invalid field (studentReviewSchema); empty when the review can be sent.
func reviewErrors(_ draft: ReviewDraft) -> [ReviewField: String] {
    var errors: [ReviewField: String] = [:]
    let quote = draft.quote.trimmed
    if quote.count < reviewQuoteMin { errors[.quote] = "Your review must be at least 20 characters." }
    if quote.count > reviewQuoteMax { errors[.quote] = "Review must be at most 1000 characters." }
    if !(1...reviewRatingMax).contains(draft.rating) { errors[.rating] = reviewRatingError }
    return errors
}

func reviewRequest(_ draft: ReviewDraft) -> ReviewRequest {
    ReviewRequest(
        quote: draft.quote.trimmed,
        rating: draft.rating,
        course: draft.course.trimmed.nilIfBlank,
        location: draft.location.trimmed.nilIfBlank
    )
}

/// A fresh form: the location starts as the student's address, as the website pre-fills it.
func newReviewDraft(_ address: String?) -> ReviewDraft { ReviewDraft(location: String((address ?? "").prefix(reviewFieldMax))) }

/// The website's badge (services/student-reviews.ts reviewStatusLabel, plus "On homepage").
func reviewStatusLabel(_ review: Review) -> (String, Tone) {
    switch review.status?.uppercased() {
    case "APPROVED": (review.featuredOnHomepage ? "On homepage" : "Approved", .success)
    case "REJECTED": ("Rejected", .danger)
    default: ("Pending approval", .warning)
    }
}

/// The "course · location" line under a submitted review, or nil when neither was given.
func reviewMeta(_ review: Review) -> String? {
    let parts = [review.course, review.location].compactMap { $0 }.filter { !$0.trimmed.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}
