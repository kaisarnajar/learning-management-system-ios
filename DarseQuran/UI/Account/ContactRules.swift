import Foundation

/// The website's contactInquirySchema limits (Android's ContactRules.kt).
let contactNameMin = 2
let contactNameMax = 100
let contactPhoneMax = 20
let contactMessageMin = 20
let contactMessageMax = 5000
private let phoneDigitsMin = 7
private let phoneDigitsMax = 15

struct ContactDraft: Equatable {
    var name: String
    var email: String
    var phone: String
    var message: String
}

/// Kotlin's Char.isDigit: any Unicode decimal digit.
func isDigitChar(_ c: Character) -> Bool {
    c.unicodeScalars.count == 1 && CharacterSet.decimalDigits.contains(c.unicodeScalars.first!)
}

private func isEmail(_ value: String) -> Bool {
    value.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil
}

/// The website's first message for an invalid form, in its field order; nil when it can be sent.
func contactError(_ draft: ContactDraft) -> String? {
    let name = draft.name.trimmed
    let digits = draft.phone.filter(isDigitChar).count
    let message = draft.message.trimmed
    if name.count < contactNameMin { return "Name must be at least 2 characters." }
    if name.count > contactNameMax { return "Name must be at most 100 characters." }
    if !isEmail(draft.email.trimmed) { return "Enter a valid email address." }
    if draft.phone.trimmed.count > contactPhoneMax { return "Phone number is too long." }
    if !draft.phone.trimmed.isEmpty, !(phoneDigitsMin...phoneDigitsMax).contains(digits) {
        return "Enter a valid phone number with 7 to 15 digits."
    }
    if message.count < contactMessageMin { return "Your message must be at least 20 characters." }
    if message.count > contactMessageMax { return "Message must be at most 5000 characters." }
    return nil
}

func contactRequest(_ draft: ContactDraft) -> ContactRequest {
    ContactRequest(
        name: draft.name.trimmed.nilIfBlank,
        email: draft.email.trimmed.nilIfBlank,
        phone: draft.phone.trimmed.nilIfBlank,
        message: draft.message.trimmed
    )
}

let contactSentTitle = "Message Sent Successfully"
let contactSent = "Thank you. Your message has been received. We aim to respond within 2–3 business days."
