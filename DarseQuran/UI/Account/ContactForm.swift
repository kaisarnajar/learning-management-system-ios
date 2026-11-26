import SwiftUI
import UIKit

// Android's ContactScreen (AccountScreens.kt) and ContactForm.kt.

struct ContactScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var loaded: AppConfig?

    var body: some View {
        let contact = (container.config ?? loaded)?.brand.contact
        DetailScaffold("Contact us") {
            ScreenColumn(spacing: 14) {
                if let contact {
                    AppCard {
                        if !contact.whatsapp.trimmed.isEmpty {
                            ContactLine(icon: .phone, text: "WhatsApp +\(contact.whatsapp)") {
                                let number = contact.whatsapp.filter(isDigitChar)
                                let text = contact.whatsappDefaultMessage.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
                                if let url = URL(string: "https://wa.me/\(number)?text=\(text)") { UIApplication.shared.open(url) }
                            }
                        }
                        if !contact.phone.trimmed.isEmpty {
                            ContactLine(icon: .phone, text: contact.phone) {
                                openOutside("tel:\(contact.phone.filter { !$0.isWhitespace })", toast: container.toaster)
                            }
                        }
                        if !contact.email.trimmed.isEmpty {
                            ContactLine(icon: .mail, text: contact.email) { openOutside("mailto:\(contact.email)", toast: container.toaster) }
                        }
                        if !contact.address.trimmed.isEmpty {
                            ContactLine(icon: .receipt, text: contact.address, action: nil)
                        }
                    }
                }
                ContactForm(user: container.session?.user)
            }
        }
        .task { if container.config == nil { loaded = await container.repo.appConfig().value } }
    }
}

private struct ContactLine: View {
    let icon: Icon
    let text: String
    let action: (() -> Void)?

    var body: some View {
        let row = HStack(spacing: 12) {
            icon.image.font(.system(size: 20)).frame(width: 24).foregroundStyle(Brand.gold).accessibilityHidden(true)
            Text(text).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { row }.buttonStyle(PressableStyle())
        } else {
            row
        }
    }
}

/// The website's contact form (components/contact/ContactForm.tsx); [user] is the signed-in account, if any.
struct ContactForm: View {
    let user: SessionUser?
    @Environment(AppContainer.self) private var container
    @State private var submitter = Submitter()
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var message = ""

    var body: some View {
        // Signed in, the website sends as the account and shows who it is from instead of the two fields.
        let draft = ContactDraft(name: user?.name ?? name, email: user?.email ?? email, phone: phone, message: message)
        let error = contactError(draft)
        Text("Send a Message").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
        Text("We would love to hear from you. Please fill out the form below and our team will get back to you within 2-3 business days.")
            .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
        if let r = submitter.result {
            Banner(r.ok ? "\(contactSentTitle). \(r.message)" : r.message, tone: r.ok ? .success : .danger)
        }
        if user == nil {
            OutlinedField(label: "Full name *", text: capped($name, contactNameMax), contentType: .name, capitalization: .words)
            OutlinedField(
                label: "Email *", text: Binding(get: { email }, set: { email = $0.trimmed }),
                keyboard: .emailAddress, contentType: .emailAddress, capitalization: .never, autocorrect: false
            )
        } else {
            Text("Submitting as \(draft.name) (\(draft.email)). We will email you when the academy replies.")
                .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
        }
        OutlinedField(
            label: "Phone / WhatsApp (optional)", text: capped($phone, contactPhoneMax), placeholder: "e.g. +919622966911",
            keyboard: .phonePad, contentType: .telephoneNumber
        )
        OutlinedField(
            label: "Your message *", text: capped($message, contactMessageMax),
            placeholder: "Tell us about your query — course enrollment, schedules, fees, or anything else…",
            supporting: "\(message.count)/\(contactMessageMax)", lines: 6...6
        )
        if let error, !message.isEmpty {
            Text(error).textStyle(Typo.bodySmall).foregroundStyle(Brand.danger)
        }
        PrimaryButton("Send message", enabled: error == nil, loading: submitter.busy) {
            let request = contactRequest(draft)
            let repo = container.repo
            submitter.submit {
                switch await repo.contact(request) {
                case .success: SubmitResult(message: contactSent, ok: true)
                case .failure(let e): SubmitResult(message: e.message, ok: false)
                }
            }
        }
        .onChange(of: submitter.result) { _, result in if result?.ok == true { message = "" } }
    }

    private func capped(_ binding: Binding<String>, _ max: Int) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = String($0.prefix(max)) })
    }
}
