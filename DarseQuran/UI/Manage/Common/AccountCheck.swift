import Observation
import SwiftUI

/// What the website said about an e-mail: the account's [name], or why it can't be used ([error]).
struct AccountAnswer: Sendable, Equatable {
    var name: String?
    var error: String? = nil

    init(_ name: String?, error: String? = nil) {
        self.name = name
        self.error = error
    }

    /// The answer of one of the website's account lookups (`{ lookup: { ok, name, error } }`), as the teacher form
    /// reads it: the name when ok, else the error.
    init(_ lookup: AccountLookup) {
        self.init(lookup.ok ? lookup.name : nil, error: lookup.ok ? nil : lookup.error)
    }
}

/// "Is this e-mail a registered account?" for staff forms (add a teacher, enrol a student, record a payment). Android's
/// AccountCheck; keep it in the screen's model:
///
///     let account = AccountCheck(app: app) { app, email in
///         AccountAnswer(try await app.service(TeachersAdminAPI.self).lookup(email: email, excludeTeacherId: nil).lookup)
///     }
///
/// Bind a field to [email] through [edit], call [verify] from "Verify account", and save only when [verified].
/// Changing the e-mail drops an answer given for the previous one, and [checking] always ends, even when a check is
/// replaced by a newer one (it used to stay on "Checking account…").
@MainActor
@Observable
final class AccountCheck {
    private(set) var email = ""
    private(set) var name = ""
    private var checkedEmail = ""
    private(set) var error: String?
    private(set) var checking = false
    @ObservationIgnored private let ask: (String) async -> ApiResult<AccountAnswer>
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// [ask] answers for one e-mail (tests give their own).
    init(ask: @escaping (String) async -> ApiResult<AccountAnswer>) {
        self.ask = ask
    }

    /// An AccountCheck whose answers come from [lookup] (one of the website's account lookups), run through apiCall.
    convenience init(app: AppContainer, lookup: @escaping @MainActor (AppContainer, String) async throws -> AccountAnswer) {
        self.init { email in await mainApiCall { try await lookup(app, email) } }
    }

    /// The e-mail as typed has been checked and belongs to an account that can be used.
    var verified: Bool { !name.trimmed.isEmpty && error == nil && checkedEmail.caseInsensitiveCompare(email.trimmed) == .orderedSame }

    /// A binding for the e-mail field.
    var emailBinding: Binding<String> { Binding(get: { self.email }, set: { self.edit($0) }) }

    func edit(_ value: String) {
        email = value
        if value.trimmed.caseInsensitiveCompare(checkedEmail) != .orderedSame { name = ""; error = nil }
    }

    /// Checks the current e-mail; [onFound] gets the account's name.
    func verify(onFound: @escaping (String) -> Void = { _ in }) {
        let target = email.trimmed
        cancel()
        if target.isEmpty { name = ""; error = nil; return }
        checking = true
        let gen = generation
        job = Task {
            let r = await ask(target)
            // A newer check (or a reset) took over: this answer is for an e-mail no longer being checked.
            guard gen == generation, !Task.isCancelled else { return }
            checking = false
            switch r {
            case .success(let answer):
                if let found = answer.name, answer.error == nil {
                    name = found; error = nil; checkedEmail = target; onFound(found)
                } else {
                    name = ""; error = answer.error ?? "This e-mail cannot be used."
                }
            case .failure(let e):
                if e.cancelled { return }
                name = ""; error = e.message
            }
        }
    }

    func reset() { cancel(); email = ""; name = ""; checkedEmail = ""; error = nil }

    /// Shows an account already linked (editing a saved record) as checked.
    func restore(email: String, name: String) { self.email = email; self.name = name; checkedEmail = email; error = nil }

    /// Stops the running check; [checking] ends with it.
    private func cancel() {
        job?.cancel()
        job = nil
        generation += 1
        checking = false
    }
}
