import Observation
import SwiftUI

// MARK: - the form (Android's AskFatwaForm.kt)

/// The website's categories (services/fatwa.ts FATWA_CATEGORIES), used until the app config has loaded.
let websiteFatwaCategories = ["Islam", "Quran", "Hadith", "Fiqh", "Tajweed", "Seerah", "Arabic Language", "Atheism", "Fatwa", "Others"]

/// The category that opens the "Specify Category" free-text field on the website.
let otherFatwaCategory = "Others"
let anonymousAsker = "Anonymous"

private let titleMin = 10
private let questionMin = 30
private let categoryMin = 2
private let categoryMax = 100
private let nameMin = 2
private let emailPattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#

/// What the ask form holds; [categoryChoice] is the picked option and [customCategory] the "Others" text.
struct AskFatwaForm: Equatable, Sendable {
    var categoryChoice = ""
    var customCategory = ""
    var title = ""
    var question = ""
    var name = ""
    var email = ""
    var anonymous = false
    /// Signed in: the name and e-mail are the account's, as on the website.
    var signedIn = false

    /// The category sent: the custom text when "Others" is picked (the website posts the typed text as `category`).
    var category: String { categoryChoice == otherFatwaCategory ? customCategory.trimmed : categoryChoice }

    /// The website's messages (utils/validations.ts fatwaQuestionSchema), by field; empty when the form can be sent.
    /// Lengths are counted as the website's JavaScript counts them (UTF-16).
    func errors() -> [AskFatwaField: String] {
        var errors: [AskFatwaField: String] = [:]
        let category = self.category
        if category.utf16.count < categoryMin { errors[.category] = "Select a topic." }
        else if category.utf16.count > categoryMax { errors[.category] = "Topic is too long." }
        if title.trimmed.utf16.count < titleMin { errors[.title] = "Title must be at least 10 characters." }
        if question.trimmed.utf16.count < questionMin { errors[.question] = "Question must be at least 30 characters." }
        if !anonymous {
            if name.trimmed.utf16.count < nameMin { errors[.name] = "Name is required." }
            if email.trimmed.range(of: emailPattern, options: .regularExpression) == nil { errors[.email] = "Enter a valid email address." }
        }
        return errors
    }

    /// The body of POST /api/v1/fatwa; an anonymous question goes as "Anonymous", as the website records it.
    func toRequest(websiteUrl: String) -> AskFatwaRequest {
        AskFatwaRequest(
            title: title.trimmed,
            question: question.trimmed,
            category: category,
            askerName: anonymous ? anonymousAsker : name.trimmed,
            askerEmail: anonymous ? anonymousEmail(websiteUrl) : email.trimmed
        )
    }

    /// The line shown instead of the name and e-mail fields when signed in (nil when they are asked for, or anonymous).
    var submittingAs: String? {
        guard signedIn, !anonymous else { return nil }
        return "Submitting as \(name) (\(email)). We will email you when answered."
    }
}

enum AskFatwaField: Hashable, Sendable { case category, title, question, name, email }

/// The e-mail the website records for an anonymous question: anonymous@ the site's host.
func anonymousEmail(_ websiteUrl: String) -> String {
    let host = URL(string: websiteUrl)?.host?.nilIfBlank ?? "darsequranacademy.com"
    return "anonymous@\(host)"
}

/// The categories offered: the app config's, or the website's list until the config has loaded.
func askFatwaOptions(_ categories: [String]) -> [String] { categories.isEmpty ? websiteFatwaCategories : categories }

// MARK: - the model (Android's AskFatwaViewModel)

@MainActor
@Observable
final class AskFatwaModel {
    private(set) var busy = false
    private(set) var error: String?
    private(set) var done = false
    private(set) var form = AskFatwaForm()
    @ObservationIgnored private let repo: AcademyRepository

    init(repo: AcademyRepository) { self.repo = repo }

    func edit(_ change: (inout AskFatwaForm) -> Void) { change(&form) }

    /// Signed in, the name and e-mail are the account's and can't be changed, as on the website.
    func account(name: String?, email: String?) {
        if let email, !email.trimmed.isEmpty {
            form.signedIn = true
            form.name = name ?? ""
            form.email = email
        } else {
            form.signedIn = false
        }
    }

    /// Sent once: a second tap while it is on its way, or after it was sent, is ignored.
    func submit(websiteUrl: String) {
        let current = form
        if busy || done || !current.errors().isEmpty { return }
        busy = true
        error = nil
        let repo = self.repo
        Task {
            switch await repo.askFatwa(current.toRequest(websiteUrl: websiteUrl)) {
            case .success: done = true
            case .failure(let e): error = e.message
            }
            busy = false
        }
    }
}

private let askFatwaSent = "Thank you. Your question has been received. We will email you when a scholar publishes an answer."

// MARK: - the screen

/// "Ask a question": the website's fatwa question form.
struct AskFatwaScreen: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        WithModel({ AskFatwaModel(repo: $0.repo) }) { model in
            AskFatwaContent(
                model: model,
                name: container.session?.user.name,
                email: container.session?.user.email,
                categories: container.config?.lookups.fatwaCategories ?? [],
                websiteUrl: container.config?.brand.websiteUrl ?? BrandInfo().websiteUrl
            )
        }
    }
}

private struct AskFatwaContent: View {
    let model: AskFatwaModel
    let name: String?
    let email: String?
    let categories: [String]
    let websiteUrl: String
    @Environment(Navigator.self) private var nav

    var body: some View {
        DetailScaffold("Ask a question") {
            if model.done {
                MessageState(icon: .fatwa, title: "Question sent", message: askFatwaSent, action: "Done") { nav.pop() }
            } else {
                form
            }
        }
        .onChange(of: "\(name ?? "")|\(email ?? "")", initial: true) { _, _ in model.account(name: name, email: email) }
    }

    private var form: some View {
        let form = model.form
        let errors = form.errors()
        // The website's list until the app config (which carries the same list) has loaded.
        let options = askFatwaOptions(categories)
        return ScreenColumn(spacing: 14) {
            Text("Submit a question on Islam, Quran, Hadith, Fiqh, Tajweed, Seerah, or related topics. We will email you when it is answered.")
                .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
            if let error = model.error { Banner(error, tone: .danger) }
            Dropdown(value: form.categoryChoice.isEmpty ? "Select a topic" : form.categoryChoice, options: options, label: "Category") { i in
                model.edit { $0.categoryChoice = options[i] }
            }
            if form.categoryChoice == otherFatwaCategory {
                FormField(label: "Specify Category", value: form.customCategory, error: errors[.category], placeholder: "Enter custom category") { v in
                    model.edit { $0.customCategory = String(v.prefix(100)) }
                }
            }
            FormField(label: "Subject", value: form.title, error: errors[.title], placeholder: "Brief summary of your question") { v in
                model.edit { $0.title = String(v.prefix(200)) }
            }
            FormField(
                label: "Your question", value: form.question, error: errors[.question],
                placeholder: "Describe your question in detail (e.g. Fiqh, Quran, Tajweed, daily practice)", lines: 6...6
            ) { v in
                model.edit { $0.question = String(v.prefix(5000)) }
            }
            CheckboxRow(checked: form.anonymous, onToggle: { model.edit { $0.anonymous.toggle() } }) {
                Text("Send Question Anonymously").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
            }
            if !form.anonymous {
                if let line = form.submittingAs {
                    Text(line).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                } else {
                    FormField(label: "Your name", value: form.name, error: errors[.name]) { v in model.edit { $0.name = String(v.prefix(100)) } }
                    FormField(
                        label: "Email", value: form.email, error: errors[.email], supporting: "We will email you when your question is answered.",
                        keyboard: .emailAddress
                    ) { v in
                        model.edit { $0.email = v.trimmed }
                    }
                }
            }
            PrimaryButton("Submit question", enabled: errors.isEmpty, loading: model.busy) { model.submit(websiteUrl: websiteUrl) }
        }
    }
}

/// A text field that shows the website's message once something has been typed (the website's "touched").
private struct FormField: View {
    let label: String
    let value: String
    let error: String?
    var placeholder: String? = nil
    var supporting: String? = nil
    var lines: ClosedRange<Int>? = nil
    var keyboard: UIKeyboardType = .default
    let onChange: @MainActor @Sendable (String) -> Void

    var body: some View {
        let shown = value.isEmpty ? nil : error
        OutlinedField(
            label: label,
            text: Binding(get: { value }, set: { v in onChange(v) }),
            placeholder: placeholder,
            error: shown,
            supporting: supporting,
            keyboard: keyboard,
            capitalization: keyboard == .emailAddress ? .never : .sentences,
            autocorrect: keyboard != .emailAddress,
            lines: lines
        )
    }
}
