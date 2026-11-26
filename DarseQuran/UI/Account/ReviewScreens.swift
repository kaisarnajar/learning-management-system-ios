import Observation
import SwiftUI

// Android's ReviewScreens.kt and ReviewsViewModel.kt.

let reviewSent = "Thank you! Your review was submitted for admin approval."

/// The student's reviews and the form for a new one (Android's ReviewsViewModel).
@MainActor
@Observable
final class ReviewsModel {
    private(set) var state: Load<[Review]> = .loading
    private(set) var sending = false
    private(set) var message: (text: String, ok: Bool)?
    private(set) var draft = ReviewDraft()
    @ObservationIgnored private var address: String?
    @ObservationIgnored private let repo: AcademyRepository
    @ObservationIgnored private let auth: AuthRepository

    init(repo: AcademyRepository, auth: AuthRepository) {
        self.repo = repo
        self.auth = auth
        load()
    }

    @discardableResult
    func load() -> Task<Void, Never> {
        Task { await loadNow() }
    }

    private func loadNow() async {
        let first = state.value == nil
        let auth = self.auth
        async let profile = first ? auth.profile().value : nil
        let reviews = await repo.myReviews().toLoad()
        if first {
            address = await profile?.address
            // The location starts as the student's address unless they already typed one.
            if draft.location.isEmpty { draft.location = newReviewDraft(address).location }
        }
        state = reviews
    }

    func edit(_ change: (inout ReviewDraft) -> Void) { change(&draft) }

    /// One review at a time: a second tap before the first is sent is ignored.
    @discardableResult
    func send() -> Task<Void, Never>? {
        if sending || !reviewErrors(draft).isEmpty { return nil }
        sending = true
        let body = reviewRequest(draft)
        return Task {
            switch await repo.addReview(body) {
            case .success:
                message = (reviewSent, true)
                draft = newReviewDraft(address)
                await loadNow()
            case .failure(let e):
                message = (e.message, false)
            }
            sending = false
        }
    }
}

struct ReviewsScreen: View {
    var body: some View {
        DetailScaffold("My reviews") {
            WithModel({ ReviewsModel(repo: $0.repo, auth: $0.auth) }) { model in
                LoadContent(state: model.state, onRetry: { model.load() }) { reviews in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            Text("Share your learning experience. Approved reviews may appear on the academy homepage.")
                                .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                            Overline(text: "Write a review")
                            ReviewForm(model: model)
                            if !reviews.isEmpty { Overline(text: "Your submissions").padding(.top, 8) }
                            ForEach(reviews) { ReviewCard(review: $0) }
                        }
                        .padding(Spacing.screen)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
    }
}

private struct ReviewForm: View {
    let model: ReviewsModel
    // The website shows a field's message once the field has been touched.
    @State private var touched: Set<ReviewField> = []

    var body: some View {
        let draft = model.draft
        let errors = reviewErrors(draft)
        let shown = { (field: ReviewField) in touched.contains(field) ? errors[field] : nil }
        AppCard {
            Text("Your rating *").textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurface)
            StarPicker(rating: draft.rating) { rating in
                model.edit { $0.rating = rating }
                touched.insert(.rating)
            }
            .padding(.leading, -12)
            if let e = shown(.rating) { Text(e).textStyle(Typo.bodySmall).foregroundStyle(Brand.danger) }
            Spacer().frame(height: 8)
            OutlinedField(
                label: "Your review *",
                text: Binding(get: { model.draft.quote }, set: { text in
                    model.edit { $0.quote = String(text.prefix(reviewQuoteMax)) }
                    touched.formUnion([.quote, .rating])
                }),
                placeholder: "Share your experience learning with Darse Quran Academy…",
                error: shown(.quote),
                supporting: "\(draft.quote.count)/\(reviewQuoteMax)",
                lines: 4...4
            )
            OptionalField(label: "Course (optional)", placeholder: "e.g. Tajweed, Hifz", value: draft.course) { text in
                model.edit { $0.course = text }
            }
            .padding(.top, 4)
            Spacer().frame(height: 8)
            OptionalField(label: "Location (optional)", placeholder: "e.g. Srinagar, J&K", value: draft.location) { text in
                model.edit { $0.location = text }
            }
            Spacer().frame(height: 10)
            Banner(
                "Your review will be sent to the admin for verification. If approved, it may appear on the homepage " +
                    "(up to \(homepageFeaturedReviewsMax) student reviews are shown at a time).",
                tone: .warning
            )
            Spacer().frame(height: 10)
            if let message = model.message {
                Banner(message.text, tone: message.ok ? .success : .danger)
                Spacer().frame(height: 8)
            }
            PrimaryButton("Submit review", enabled: errors.isEmpty, loading: model.sending) { model.send() }
        }
    }
}

private struct StarPicker: View {
    let rating: Int
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...reviewRatingMax, id: \.self) { i in
                IconButton(i <= rating ? .star : .starOutline, label: "\(i) stars", tint: Brand.goldSoft) { onPick(i) }
                    .accessibilityAddTraits(i == rating ? .isSelected : [])
            }
        }
    }
}

private struct OptionalField: View {
    let label: String
    let placeholder: String
    let value: String
    let onChange: (String) -> Void

    var body: some View {
        OutlinedField(
            label: label,
            text: Binding(get: { value }, set: { onChange(String($0.prefix(reviewFieldMax))) }),
            placeholder: placeholder
        )
    }
}

private struct ReviewCard: View {
    let review: Review

    var body: some View {
        let r = review
        let (label, tone) = reviewStatusLabel(r)
        AppCard {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<max(0, r.rating), id: \.self) { _ in
                        Icon.star.image.font(.system(size: 13)).frame(width: 16, height: 16).foregroundStyle(Brand.goldSoft)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.rating) stars")
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusChip(label, tone: tone)
            }
            Spacer().frame(height: 6)
            Text("“\(r.quote)”").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
            if let meta = reviewMeta(r) {
                Text(meta).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).padding(.top, 4)
            }
            Text("Submitted \(formatDate(r.createdAt))").textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
        }
    }
}
