import Observation
import SwiftUI

/*
 * Student reviews: /admin/review-approvals (pending and approved), one review, and its homepage settings.
 * Ported from Android's ui/manage/people/Reviews.kt.
 */

private let reviewsApproved = "approved"

/// A review's status tone.
func reviewTone(_ status: String) -> Tone {
    switch status {
    case "APPROVED": .success
    case "REJECTED": .danger
    default: .warning
    }
}

/// A review action waiting for the admin's confirmation.
enum ReviewAsk {
    case approve(StudentReviewRow, feature: Bool = false)
    case reject(StudentReviewRow)
    case delete(StudentReviewRow)

    var isDelete: Bool { if case .delete = self { true } else { false } }
}

extension View {
    /// Confirmations for review actions, shared by the list, detail and edit screens (Android's ReviewAskDialog).
    func reviewAskDialog(_ ask: Binding<ReviewAsk?>, runner: ActionRunner, onDone: @escaping (ReviewAsk) -> Void) -> some View {
        let title: String = switch ask.wrappedValue {
        case .approve: "Approve review"
        case .reject: "Reject review"
        case .delete(let r): "Delete review by \(r.user.name ?? r.user.email)?"
        case nil: ""
        }
        let shown = Binding(get: { ask.wrappedValue != nil }, set: { if !$0 { ask.wrappedValue = nil } })
        return alert(title, isPresented: shown, presenting: ask.wrappedValue) { a in
            Button("Cancel", role: .cancel) {}
            switch a {
            case .approve(let r, let feature):
                Button("Approve") {
                    runner.run(
                        { try await $0.service(ReviewsAdminAPI.self).approve(r.id, formOf { $0.check("featureOnHomepage", feature) }) },
                        success: "Review updated."
                    ) { _ in onDone(a) }
                }
            case .reject(let r):
                Button("Reject", role: .destructive) {
                    runner.run(
                        { try await $0.service(ReviewsAdminAPI.self).reject(r.id) },
                        success: "Review rejected. The student can edit and resubmit."
                    ) { _ in onDone(a) }
                }
            case .delete(let r):
                Button("Delete", role: .destructive) {
                    runner.run({ try await $0.service(ReviewsAdminAPI.self).delete(r.id) }, success: "Review deleted.") { _ in onDone(a) }
                }
            }
        } message: { a in
            switch a {
            case .approve(_, let feature):
                Text(feature ? "Approve this student review and show it on the homepage?" : "Approve this student review?")
            case .reject: Text("Reject this review? The student can edit and resubmit.")
            case .delete: Text("The review is removed permanently.")
            }
        }
    }
}

// MARK: - list

@MainActor
@Observable
final class ReviewsListModel {
    let list: PagedListModel<StudentReviewRow>
    let summary: Loader<ReviewsSummary>
    let runner: ActionRunner
    var asking: ReviewAsk?

    init(app: AppContainer) {
        list = PagedListModel(app: app) { app, page, q, type in
            try await app.service(ReviewsAdminAPI.self).list(page: page, q: q.trimmed.isEmpty ? nil : q, type: type)
        }
        summary = Loader(app: app) { try await $0.service(ReviewsAdminAPI.self).summary() }
        runner = ActionRunner(app: app)
    }

    func reload() { list.refresh(); summary.reload() }
}

/// /admin/review-approvals: pending reviews to approve or reject, and every approved review (homepage visibility).
struct ReviewsListScreen: View {
    var body: some View {
        WithModel({ ReviewsListModel(app: $0) }) { model in ReviewsListContent(model: model) }
    }
}

private struct ReviewsListContent: View {
    @Bindable var model: ReviewsListModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let counts = model.summary.state.value
        let approved = model.list.state.filter == reviewsApproved
        let busy = model.runner.busy
        ManageListScreen(
            "Reviews", model: model.list, key: \.id,
            emptyTitle: approved ? "No approved reviews yet" : "No student reviews awaiting approval",
            searchHint: "Name, e-mail, course or review text",
            filters: [
                FilterOption(nil, "Pending" + reviewsCount(counts?.pendingCount)),
                FilterOption(reviewsApproved, "Approved" + reviewsCount(counts?.approvedCount)),
            ],
            header: {
                Text(
                    approved
                        ? "Every approved review stays here. Use Edit to add or remove homepage visibility."
                            + (counts.map { " \($0.featuredCount) / \($0.featuredMax) featured on homepage." } ?? "")
                        : "Student reviews awaiting your approval before they can be featured."
                )
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        ) { r in
            PeopleActionCard(
                title: r.user.name ?? "—",
                subtitle: [r.user.email, r.courseLabel, r.location.flatMap { $0.trimmed.isEmpty ? nil : $0 }].compactMap { $0 }.joined(separator: " · "),
                meta: "Submitted " + formatDate(r.createdAt) + (approved ? (r.featuredOnHomepage ? " · Featured" : " · Not featured") : ""),
                body: "“\(r.quote)”",
                onClick: { nav.push(.manage(.reviewAdmin(id: r.id))) },
                leading: { PeopleStars(r.rating, size: 14) }
            ) {
                PeopleSmallOutlined("Edit") { nav.push(.manage(.reviewEdit(id: r.id))) }
                if approved {
                    PeopleSmallDanger("Delete", enabled: !busy) { model.asking = .delete(r) }
                } else {
                    PeopleSmallPrimary("Approve", enabled: !busy) { model.asking = .approve(r) }
                    PeopleSmallDanger("Reject", enabled: !busy) { model.asking = .reject(r) }
                }
            }
        }
        .reloadOnReturn { model.reload() }
        .reviewAskDialog($model.asking, runner: model.runner) { _ in model.reload() }
    }
}

private func reviewsCount(_ n: Int?) -> String { if let n, n > 0 { " (\(n))" } else { "" } }

// MARK: - one review

@MainActor
@Observable
final class ReviewDetailModel {
    let loader: Loader<ReviewResponse>
    let runner: ActionRunner
    var asking: ReviewAsk?

    init(app: AppContainer, id: String) {
        loader = Loader(app: app) { try await $0.service(ReviewsAdminAPI.self).get(id) }
        runner = ActionRunner(app: app)
    }
}

/// /admin/review-approvals/[id].
struct ReviewDetailScreen: View {
    let id: String

    var body: some View {
        WithModel({ ReviewDetailModel(app: $0, id: id) }) { model in ReviewDetailContent(id: id, model: model) }
    }
}

private struct ReviewDetailContent: View {
    let id: String
    @Bindable var model: ReviewDetailModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let review = model.loader.state.value?.review
        let busy = model.runner.busy
        ManageScaffold("Student review", actions: {
            if let review, review.status != "REJECTED" {
                IconButton(.edit, label: "Edit") { nav.push(.manage(.reviewEdit(id: id))) }
            }
            if let review, review.status != "PENDING" {
                IconButton(.delete, label: "Delete review") { model.asking = .delete(review) }
            }
        }) {
            LoadedColumn(model.loader) { data in
                let r = data.review
                DetailCard {
                    Field("Name", r.user.name)
                    Field("Email", r.user.email)
                    Field("Course", r.courseLabel)
                    Field("Location", r.location)
                    StatusChip(r.statusLabel.trimmed.isEmpty ? r.status : r.statusLabel, tone: reviewTone(r.status))
                    if r.status == "APPROVED" { Field("Homepage", r.featuredOnHomepage ? "Featured" : "Not featured") }
                }
                DetailCard {
                    HStack(spacing: 12) {
                        PeopleStars(r.rating)
                        Text(formatDate(r.createdAt)).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                    Text(r.quote).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                }
                if r.status == "PENDING" {
                    HStack(spacing: 8) {
                        PeopleSmallPrimary("Approve", enabled: !busy) { model.asking = .approve(r) }
                        PeopleSmallDanger("Reject", enabled: !busy) { model.asking = .reject(r) }
                    }
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .reviewAskDialog($model.asking, runner: model.runner) { ask in if ask.isDelete { nav.pop() } else { model.loader.reload() } }
    }
}

// MARK: - edit

@MainActor
@Observable
final class ReviewEditModel {
    let loader: Loader<ReviewResponse>
    let runner: ActionRunner
    var asking: ReviewAsk?
    var feature = false
    var loaded = false

    init(app: AppContainer, id: String) {
        loader = Loader(app: app) { try await $0.service(ReviewsAdminAPI.self).get(id) }
        runner = ActionRunner(app: app)
    }

    func fill() {
        guard let data = loader.state.value, !loaded else { return }
        feature = data.review.featuredOnHomepage
        loaded = true
    }
}

/// /admin/review-approvals/[id]/edit: homepage visibility, and approve/reject while pending.
struct ReviewEditScreen: View {
    let id: String

    var body: some View {
        WithModel({ ReviewEditModel(app: $0, id: id) }) { model in ReviewEditContent(id: id, model: model) }
    }
}

private struct ReviewEditContent: View {
    let id: String
    @Bindable var model: ReviewEditModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let title = model.loader.state.value?.review.status == "PENDING" ? "Review submission" : "Edit review settings"
        let runner = model.runner
        ManageScaffold(title) {
            LoadedColumn(model.loader) { d in
                let r = d.review
                if r.status == "REJECTED" {
                    Notice("This review was rejected; the student can edit and resubmit it.", tone: .info)
                } else {
                    Notice(
                        "Review content was submitted by the student and cannot be changed here. You can manage homepage visibility below.",
                        tone: .warning
                    )
                    DetailCard {
                        Field("Name", r.user.name)
                        Field("Email", r.user.email)
                        Field("Course", r.courseLabel)
                        Field("Location", r.location)
                        PeopleStars(r.rating)
                        Field("Review", "“\(r.quote)”")
                        Field("Submitted", formatDate(r.createdAt))
                    }
                    DetailCard {
                        let canChoose = d.canFeature || model.feature
                        FormSwitch(
                            "Show on homepage", checked: model.feature,
                            description: "Featured in the student reviews section on the homepage (up to \(d.featuredMax); \(d.featuredCount)/\(d.featuredMax) slots used)."
                        ) { new in if canChoose && !runner.busy { model.feature = new } }
                        if !d.canFeature {
                            Text("The homepage already has \(d.featuredMax) reviews. Remove one before featuring this review.")
                                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                        }
                    }
                    HStack(spacing: 8) {
                        if r.status == "PENDING" {
                            PeopleSmallPrimary("Approve", enabled: !runner.busy) { model.asking = .approve(r, feature: model.feature) }
                            PeopleSmallDanger("Reject", enabled: !runner.busy) { model.asking = .reject(r) }
                        } else {
                            PeopleSmallPrimary("Save changes", enabled: !runner.busy) {
                                let feature = model.feature
                                runner.run(
                                    { try await $0.service(ReviewsAdminAPI.self).saveHomepage(id, formOf { $0.check("featuredOnHomepage", feature) }) },
                                    success: "Homepage settings saved."
                                ) { _ in nav.pop() }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: model.loader.state.value?.review.id, initial: true) { _, _ in model.fill() }
        .reviewAskDialog($model.asking, runner: runner) { _ in nav.pop() }
    }
}
