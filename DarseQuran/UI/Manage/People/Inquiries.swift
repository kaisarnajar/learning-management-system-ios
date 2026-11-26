import Observation
import SwiftUI

/*
 * Contact inquiries: /admin/contact-inquiries (list), one inquiry, and the reply form. Ported from Android's
 * ui/manage/people/Inquiries.kt.
 */

private func inquiryChip(_ i: ContactInquiry) -> (String, Tone) {
    (i.statusLabel.trimmed.isEmpty ? (i.reply != nil ? "Replied" : "Pending") : i.statusLabel, i.reply != nil ? .success : .warning)
}

private func inquiryRepliedLine(_ i: ContactInquiry) -> String? {
    i.repliedAt.map { formatDate($0) + (i.repliedBy?.name.map { " by \($0)" } ?? "") }
}

/// What the website's toast says after a reply, by whether the e-mail went out.
func inquiryReplySavedMessage(_ r: ActionResponse) -> String {
    "Reply saved." + {
        switch r.emailOutcome() {
        case .failed, .anonymous: " The notification email could not be sent — check SMTP settings in your environment."
        case .notConfigured: " SMTP is not configured, so no email was sent."
        case .sent: " The visitor has been notified by email. If they don't see it, ask them to check their Spam/Junk folder."
        }
    }()
}

// MARK: - list

@MainActor
@Observable
final class InquiriesListModel {
    let list: PagedListModel<ContactInquiry>
    let runner: ActionRunner
    var deleting: ContactInquiry?

    init(app: AppContainer) {
        list = PagedListModel(app: app) { app, page, q, filter in
            try await app.service(ContactInquiriesAPI.self).list(page: page, q: q.trimmed.isEmpty ? nil : q, filter: filter)
        }
        runner = ActionRunner(app: app)
    }
}

struct InquiriesListScreen: View {
    var body: some View {
        WithModel({ InquiriesListModel(app: $0) }) { model in InquiriesListContent(model: model) }
    }
}

private struct InquiriesListContent: View {
    @Bindable var model: InquiriesListModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let busy = model.runner.busy
        ManageListScreen(
            "Contact inquiries", model: model.list, key: \.id, emptyTitle: "No contact messages yet",
            searchHint: "Name, e-mail, phone or message",
            filters: [FilterOption(nil, "All"), FilterOption("pending", "Pending"), FilterOption("replied", "Replied")]
        ) { i in
            PeopleActionCard(
                title: i.name,
                subtitle: [i.email, i.phone].filter { !$0.trimmed.isEmpty }.joined(separator: " · "),
                meta: "Submitted " + formatDate(i.createdAt),
                chip: inquiryChip(i),
                body: i.message,
                onClick: { nav.push(.manage(.inquiryAdmin(id: i.id))) }
            ) {
                PeopleSmallOutlined(i.reply != nil ? "Edit reply" : "Reply") { nav.push(.manage(.inquiryReply(id: i.id))) }
                PeopleSmallDanger("Delete", enabled: !busy) { model.deleting = i }
            }
        }
        .reloadOnReturn { model.list.refresh() }
        .confirmDialog(
            item: $model.deleting, title: "Delete this inquiry?",
            message: { "\($0.name) (\($0.email)) — the message is removed permanently." }, confirm: "Delete", destructive: true
        ) { i in
            model.runner.run({ try await $0.service(ContactInquiriesAPI.self).delete(i.id) }, success: "Inquiry deleted.") { _ in model.list.refresh() }
        }
    }
}

// MARK: - one inquiry

@MainActor
@Observable
final class InquiryDetailModel {
    let loader: Loader<ContactInquiry>
    let runner: ActionRunner
    var confirmDelete = false

    init(app: AppContainer, id: String) {
        loader = Loader(app: app) { try await $0.service(ContactInquiriesAPI.self).get(id).inquiry }
        runner = ActionRunner(app: app)
    }
}

struct InquiryDetailScreen: View {
    let id: String

    var body: some View {
        WithModel({ InquiryDetailModel(app: $0, id: id) }) { model in InquiryDetailContent(id: id, model: model) }
    }
}

private struct InquiryDetailContent: View {
    let id: String
    @Bindable var model: InquiryDetailModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let reply = { nav.push(.manage(.inquiryReply(id: id))) }
        ManageScaffold("Contact inquiry", actions: {
            IconButton(.reply, label: "Reply", action: reply)
            IconButton(.delete, label: "Delete inquiry") { model.confirmDelete = true }
        }) {
            LoadedColumn(model.loader) { i in
                DetailCard {
                    Field("Name", i.name)
                    Field("Email", i.email)
                    Field("Phone", i.phone)
                    let chip = inquiryChip(i)
                    StatusChip(chip.0, tone: chip.1)
                    Field("Message", i.message)
                    Field("Reply", i.reply, showEmpty: false)
                    Field("Replied", inquiryRepliedLine(i), showEmpty: false)
                    Field("Submitted", formatDate(i.createdAt))
                }
                PeopleSmallPrimary(i.reply != nil ? "Edit reply" : "Reply", action: reply)
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog("Delete this inquiry?", message: "The message is removed permanently.", isPresented: $model.confirmDelete, confirm: "Delete", destructive: true) {
            model.runner.run({ try await $0.service(ContactInquiriesAPI.self).delete(id) }, success: "Inquiry deleted.") { _ in nav.pop() }
        }
    }
}

// MARK: - reply

@MainActor
@Observable
final class InquiryReplyModel {
    let id: String
    let loader: Loader<ContactInquiry>
    let runner: ActionRunner
    var reply = ""
    var loaded = false
    var error: String?
    var confirmDelete = false

    init(app: AppContainer, id: String) {
        self.id = id
        loader = Loader(app: app) { try await $0.service(ContactInquiriesAPI.self).get(id).inquiry }
        runner = ActionRunner(app: app)
    }

    func fill() {
        guard let i = loader.state.value, !loaded else { return }
        reply = i.reply ?? ""
        loaded = true
    }

    func save() {
        error = reply.trimmed.count < 10 ? "The reply must be at least 10 characters." : nil
        guard error == nil else { return }
        let id = id, text = reply.trimmed
        runner.run({ try await $0.service(ContactInquiriesAPI.self).reply(id, formOf { $0.text("reply", text) }) }) { [weak self] r in
            guard let self else { return }
            self.runner.message(inquiryReplySavedMessage(r))
            self.loader.reload()
        }
    }
}

/// /admin/contact-inquiries/[id]/reply: the reply is saved and e-mailed to the visitor.
struct InquiryReplyScreen: View {
    let id: String

    var body: some View {
        WithModel({ InquiryReplyModel(app: $0, id: id) }) { model in InquiryReplyContent(model: model) }
    }
}

private struct InquiryReplyContent: View {
    @Bindable var model: InquiryReplyModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = model.loader.state
        let inquiry = state.value
        let replied = inquiry?.reply != nil
        let loadError: String? = if case .failed(let message) = state { message } else { nil }
        FormScreen(
            replied ? "Edit reply" : "Reply to inquiry", saving: model.runner.busy,
            saveLabel: replied ? "Update reply & resend email" : "Send reply", error: model.error, canSave: model.loaded,
            loadError: loadError, onRetry: { model.loader.load() }, onSave: { model.save() }
        ) {
            if let i = inquiry {
                if let line = inquiryRepliedLine(i) {
                    Text((replied ? "Replied " : "Last updated ") + line).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                DetailCard {
                    Text(i.name).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                    Text("\(i.email) · \(i.phone)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    Text(i.message).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                }
                FormTextField(
                    replied ? "Update reply" : "Reply to visitor", text: $model.reply,
                    supporting: "Minimum 10 characters. The visitor will receive this reply by email.", singleLine: false, minLines: 8,
                    maxLength: 10000
                )
                HStack {
                    PeopleSmallDanger("Delete inquiry", enabled: !model.runner.busy) { model.confirmDelete = true }
                    Spacer()
                }
            } else {
                Text("Loading…").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
            }
        }
        .onChange(of: inquiry?.id, initial: true) { _, _ in model.fill() }
        .confirmDialog("Delete this inquiry?", message: "The message is removed permanently.", isPresented: $model.confirmDelete, confirm: "Delete", destructive: true) {
            let id = model.id
            model.runner.run({ try await $0.service(ContactInquiriesAPI.self).delete(id) }, success: "Inquiry deleted.") { _ in nav.pop() }
        }
    }
}
