import Observation
import SwiftUI

// Website: /admin/fatwa (+ [id]) for admins, /teacher/fatwa (+ [id]) for teachers. Both answer with the same editor.
// Ported from Android's ui/manage/content/Fatwa.kt.

/// Whose fatwa screens these are: the admin's, or a teacher's assigned questions (Android's FatwaAudience).
enum FatwaAudience: Hashable, Sendable { case admin, teacher }

private let fatwaFilters = [
    FilterOption(nil, "All"),
    FilterOption("unanswered", "Unanswered"),
    FilterOption("pending", "Pending Review"),
    FilterOption("answered", "Answered"),
    FilterOption("rejected", "Rejected"),
]

private func deleteFatwaMessage(_ title: String) -> String { "\"\(title)\" and its answer are removed for good." }

// MARK: - list

@MainActor
final class ManageFatwaListModel {
    let list: PagedListModel<FatwaRow>
    let runner: ActionRunner

    init(app: AppContainer, audience: FatwaAudience) {
        let admin = audience == .admin
        list = PagedListModel(app: app) { app, page, q, filter in
            let api = app.service(ContentAPI.self)
            let query = q.trimmed.isEmpty ? nil : q
            return admin ? try await api.fatwas(page: page, q: query, filter: filter) : try await api.teacherFatwas(page: page, q: query, filter: filter)
        }
        runner = ActionRunner(app: app)
    }
}

// Android's FatwaListScreen; renamed because the student app's fatwa list already has that name.
struct ManageFatwaListScreen: View {
    let audience: FatwaAudience

    var body: some View {
        WithModel({ ManageFatwaListModel(app: $0, audience: audience) }) { model in ManageFatwaListContent(audience: audience, model: model) }
    }
}

private struct ManageFatwaListContent: View {
    let audience: FatwaAudience
    let model: ManageFatwaListModel
    @Environment(Navigator.self) private var nav
    @State private var deleting: FatwaRow?

    var body: some View {
        let admin = audience == .admin
        let open: (String) -> Void = { id in nav.push(.manage(admin ? .fatwaAdminDetail(id: id) : .teacherFatwaDetail(id: id))) }
        ManageListScreen(
            "Fatwa Q&A", model: model.list, key: \.id,
            emptyTitle: admin ? "No questions yet" : "No questions available",
            searchHint: admin ? "Search by subject, asker, e-mail or category" : "Search by subject, question or category",
            filters: fatwaFilters,
            header: {
                Text("\(model.list.state.total) questions").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        ) { q in
            let action = q.approvalStatus == "PENDING" ? "Review" : !q.answered ? "Answer" : admin ? "Edit" : "View/Edit"
            RecordCard(
                title: q.title,
                subtitle: admin ? ([q.category] + [q.askerName].compactMap { $0 } + [q.askerEmail ?? "N/A"]).joined(separator: " · ") : q.category,
                meta: "Submitted " + formatDate(q.createdAt) + (admin ? " · " + (q.featuredOnHomepage ? "Featured" : "Not featured") : ""),
                chip: (q.statusLabel, contentTone(q.statusLabel)),
                onClick: { open(q.id) },
                leading: { RowIcon(.questionAnswer) },
                trailing: {
                    ContentRowMenu([
                        ContentRowAction(action) { open(q.id) },
                        q.publicPath.map { path in ContentRowAction("View on website") { openWeb(path) } },
                        admin ? ContentRowAction("Delete", destructive: true) { deleting = q } : nil,
                    ])
                }
            )
        }
        .reloadOnReturn { model.list.refresh() }
        .confirmDialog(item: $deleting, title: "Delete this question?", message: { deleteFatwaMessage($0.title) }, confirm: "Delete", destructive: true) { q in
            model.runner.run({ try await $0.service(ContentAPI.self).deleteFatwa(q.id) }, success: "Question deleted.") { _ in model.list.refresh() }
        }
    }
}

// MARK: - answer

/// What the website's toast says after an admin publishes an answer (`email=` on its redirect).
private func answerPublishedMessage(_ response: ActionResponse) -> String {
    "Answer published. " + {
        switch response.emailOutcome() {
        case .anonymous: "No notification e-mail is sent for an anonymous question."
        case .failed: "The notification e-mail could not be sent. Check the SMTP settings."
        case .notConfigured: "SMTP is not configured, so no e-mail was sent."
        case .sent: "The asker has been notified by e-mail (ask them to check Spam if it does not arrive)."
        }
    }()
}

@MainActor
@Observable
final class FatwaAnswerModel {
    let audience: FatwaAudience
    let id: String
    let loader: Loader<FatwaAdminResponse>
    let runner: ActionRunner
    var answer: String?
    var featured: Bool?

    init(app: AppContainer, audience: FatwaAudience, id: String) {
        self.audience = audience
        self.id = id
        let admin = audience == .admin
        loader = Loader(app: app) { admin ? try await $0.service(ContentAPI.self).fatwa(id) : try await $0.service(ContentAPI.self).teacherFatwa(id) }
        runner = ActionRunner(app: app)
    }

    var admin: Bool { audience == .admin }
    var question: FatwaDetail? { loader.state.value?.question }

    func fillOnce() {
        guard let q = question else { return }
        if answer == nil { answer = q.answer ?? "" }
        if featured == nil { featured = q.featuredOnHomepage }
    }

    /// Pending answers are approved or rejected as they are; otherwise the edited text is sent.
    private func answerParts(_ q: FatwaDetail, editable: Bool, withFeatured: Bool) -> FormBody {
        let text = editable ? toWebsiteHtml(answer ?? q.answer ?? "") : (q.answer ?? "")
        let feature = featured ?? q.featuredOnHomepage
        return formOf { f in
            f.text("answer", text)
            if withFeatured { f.check("featuredOnHomepage", feature) }
        }
    }

    func publish(_ q: FatwaDetail, editable: Bool) {
        let text = editable ? (answer ?? q.answer ?? "") : (q.answer ?? "")
        // The website requires an answer of at least 20 characters; say so here rather than after a round trip.
        if let problem = answerProblem(text) { runner.message(problem); return }
        let (id, parts) = (id, answerParts(q, editable: editable, withFeatured: true))
        runner.run({ try await $0.service(ContentAPI.self).answerFatwa(id, parts) }) { [weak self] response in
            self?.runner.message(answerPublishedMessage(response))
            self?.loader.reload()
        }
    }

    func submitDraft(_ q: FatwaDetail, editable: Bool) {
        let (id, parts) = (id, answerParts(q, editable: editable, withFeatured: false))
        runner.run({ try await $0.service(ContentAPI.self).answerTeacherFatwa(id, parts) }, success: "Draft saved and submitted for admin approval.") { [weak self] _ in
            self?.loader.reload()
        }
    }

    func reject() {
        let (id, a) = (id, question?.answer ?? "")
        runner.run({ try await $0.service(ContentAPI.self).rejectFatwa(id, formOf { $0.text("answer", a) }) }, success: "Answer rejected.") { [weak self] _ in
            self?.loader.reload()
        }
    }
}

/// Answer a question. Admins publish (or update) the answer, approve or reject a teacher's pending one, feature it on
/// the homepage and delete the question; teachers draft an answer for review (locked while pending and once approved).
struct FatwaAnswerScreen: View {
    let audience: FatwaAudience
    let id: String

    var body: some View {
        WithModel({ FatwaAnswerModel(app: $0, audience: audience, id: id) }) { model in FatwaAnswerContent(model: model) }
    }
}

private struct FatwaAnswerContent: View {
    let model: FatwaAnswerModel
    @Environment(Navigator.self) private var nav
    @State private var confirmReject = false
    @State private var confirmDelete = false

    var body: some View {
        let admin = model.admin
        let q = model.question
        let title = if let q {
            !admin ? (q.answered ? "Edit draft answer" : "Draft answer")
                : q.approvalStatus == "PENDING" ? "Review pending answer"
                : q.answered ? "Edit answer"
                : "Answer question"
        } else {
            "Fatwa question"
        }
        ManageScaffold(title, actions: {
            if admin { IconButton(.delete, label: "Delete question") { confirmDelete = true } }
        }) {
            LoadedColumn(model.loader) { data in content(data) }
        }
        .onChange(of: q != nil, initial: true) { _, ready in if ready { model.fillOnce() } }
        .confirmDialog(
            "Reject this answer?", message: "The teacher is told by e-mail and can revise and resubmit it.",
            isPresented: $confirmReject, confirm: "Reject", destructive: true
        ) { model.reject() }
        .confirmDialog(
            "Delete this question?", message: deleteFatwaMessage(q?.title ?? "This question"),
            isPresented: $confirmDelete, confirm: "Delete", destructive: true
        ) {
            let id = model.id
            model.runner.run({ try await $0.service(ContentAPI.self).deleteFatwa(id) }, success: "Question deleted.") { _ in nav.pop() }
        }
    }

    @ViewBuilder private func content(_ data: FatwaAdminResponse) -> some View {
        let admin = model.admin
        let question = data.question
        let pending = question.approvalStatus == "PENDING"
        let editable = admin ? !pending : question.canEdit
        DetailCard {
            Text(question.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
            Text(question.question).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
            Text(
                ([question.category]
                    + (admin && !question.anonymous ? [question.askerName].compactMap { $0 } + [question.askerEmail ?? "N/A"] : []))
                    .joined(separator: " · ")
            )
            .textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
            HStack(spacing: 8) { StatusChip(question.statusLabel, tone: contentTone(question.statusLabel)) }
        }
        if admin, question.answered, let answeredAt = question.answeredAt {
            Text(
                "First answered \(formatDate(answeredAt)) · " + (
                    question.approvalStatus == "APPROVED" ? "Visible on the public Fatwa section"
                        : question.approvalStatus == "PENDING" ? "Pending your approval"
                        : "Rejected"
                )
            )
            .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
        } else if !admin, question.answered {
            Text(
                "Status: " + (
                    question.approvalStatus == "PENDING" ? "Pending Admin Approval"
                        : question.approvalStatus == "REJECTED" ? "Rejected"
                        : "Approved and Published"
                )
            )
            .textStyle(Typo.titleSmall)
            .foregroundStyle(
                question.approvalStatus == "PENDING" ? Brand.warning : question.approvalStatus == "REJECTED" ? Scheme.error : Scheme.primary
            )
        }
        VStack(alignment: .leading, spacing: 0) {
            let label = admin ? (question.answered ? "Update answer" : "Publish answer") : (question.answered ? "Update draft" : "Submit draft for review")
            if editable {
                RichTextField(label, initialHtml: model.answer ?? question.answer ?? "") { model.answer = $0 }
            } else {
                DetailCard(label) { HtmlText(html: question.answer ?? "") }
            }
            Text(
                admin && pending ? "You are reviewing a submitted answer. It cannot be edited directly."
                    : admin ? "Minimum 20 characters. The asker will be e-mailed when you save."
                    : question.approvalStatus == "APPROVED" && question.answered ? "This answer is approved and published. It can no longer be edited."
                    : pending ? "This draft is pending review by the admin. You cannot edit it unless it is rejected."
                    : "Minimum 20 characters. The admin will be notified to review it."
            )
            .textStyle(Typo.bodySmall)
            .foregroundStyle(!admin && !editable ? Brand.warning : Scheme.onSurfaceVariant)
        }
        if admin {
            FeaturedSwitch(
                featured: model.featured ?? question.featuredOnHomepage, currentlyFeatured: question.featuredOnHomepage,
                used: data.featuredCount, max: data.featuredMax, section: "Fatwa", pageName: "Fatwa page", noun: "answers",
                condition: "when this answer is published"
            ) { model.featured = $0 }
        }
        VStack(alignment: .leading, spacing: 0) {
            if admin {
                PrimaryButton(pending ? "Approve & Publish" : question.answered ? "Update answer" : "Publish answer", loading: model.runner.busy) {
                    model.publish(question, editable: editable)
                }
                if pending {
                    ContentOutlinedButton("Reject", color: Scheme.error, fullWidth: true, enabled: !model.runner.busy) { confirmReject = true }
                }
            } else if editable {
                PrimaryButton(question.answered ? "Update draft" : "Submit draft", loading: model.runner.busy) {
                    model.submitDraft(question, editable: editable)
                }
            }
        }
        if let path = question.publicPath {
            ContentOutlinedButton("Public link: \(path)") { openWeb(path) }
        }
        if admin && question.anonymous { Banner("Anonymous question: no notification e-mail is sent to the asker.", tone: .info) }
    }
}
