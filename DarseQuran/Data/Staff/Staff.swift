import Foundation

/*
 * Shared pieces of the admin and teacher API (/api/v1/admin, /api/v1/teacher), ported from Android's
 * data/staff/Staff.kt.
 *
 * Writes run the website's own server actions, so their bodies are the same form fields the website's forms send:
 * text fields as they are, a ticked checkbox as "on" (an unticked one is left out), files as multipart parts
 * ([FormFields], [formOf]). Every write answers with [ActionResponse].
 *
 * The API structs (StudentsAdminAPI, MoneyAPI, …) are thin wrappers over [APIClient] whose methods throw, like
 * AcademyAPI; Android wraps its Retrofit calls in `apiCall` where they are made (the admin kit's loaders, paged
 * lists and ActionRunner do it), and so do the iOS kit's `Loader(app:)`, `PagedListModel(app:)` and `ActionRunner`.
 * Get one with `app.service(StudentsAdminAPI.self)` (Android's `service<StudentsAdminApi>()`).
 *
 * `{ success, data, totalCount, page, pageSize }` lists are read with the app's existing `Paged<T>`.
 */

/// A staff API: a small struct over the shared [APIClient] (Android's Retrofit service interface).
protocol StaffService: Sendable {
    init(client: APIClient)
}

extension AppContainer {
    /// The staff API [type], over the app's client (Android's `AppContainer.service<T>()`).
    func service<S: StaffService>(_ type: S.Type) -> S { S(client: client) }
}

// MARK: - write answers

/// The answer to a write. [redirect] is where the website would have gone next (it can carry a new record's id).
struct ActionResponse: Model {
    @Default<True> var success: Bool = true
    var redirect: String? = nil
    var result: JSONValue? = nil

    /// A string field of [result], e.g. `stringResult("id")`.
    func stringResult(_ key: String) -> String? {
        guard case .object(let fields) = result else { return nil }
        return fields[key]?.text
    }

    /// Whether the notification e-mail went out. The website adds `email=anonymous|skipped|failed` to [redirect] when
    /// it didn't (fatwa answers, inquiry replies); no such parameter means it was sent.
    func emailOutcome() -> EmailOutcome {
        guard let redirect, let match = redirect.firstMatch(of: /[?&]email=([^&#]+)/) else { return .sent }
        switch String(match.1) {
        case "anonymous": return .anonymous
        case "skipped": return .notConfigured
        default: return .failed
        }
    }
}

/// What happened to the notification e-mail of a write; see [ActionResponse.emailOutcome].
enum EmailOutcome: Sendable { case sent, anonymous, notConfigured, failed }

// MARK: - loosely typed JSON

/// Any JSON value (Kotlin's JsonElement): for loosely typed fields such as a write's `result` or an audit entry's
/// `before` / `after`.
enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// The content of a primitive as text (a string as is, a number or boolean as written), nil for null, arrays and
    /// objects (Android's `JsonElement?.asText()`).
    var text: String? {
        switch self {
        case .string(let s): s
        case .bool(let b): b ? "true" : "false"
        case .int(let i): String(i)
        case .double(let d): String(d)
        case .null, .array, .object: nil
        }
    }

    /// The fields of an object (nil for anything else).
    var object: [String: JSONValue]? { if case .object(let o) = self { o } else { nil } }
}

extension Optional where Wrapped == JSONValue {
    /// Android's `JsonElement?.asText()`.
    var text: String? { self?.text }
}

// MARK: - multipart forms

/// A server-action body: text fields and files, in the multipart form the website's forms send.
struct FormBody: Sendable {
    var fields: [(String, String)] = []
    var files: [FilePart] = []
}

/// Builds the multipart body of a server-action call (Android's FormFields):
///
///     api.update(id, formOf { f in
///         f.text("name", name.trimmed)
///         f.check("published", published)
///         f.file("image", picked)
///     })
struct FormFields {
    private(set) var fields: [(String, String)] = []
    private(set) var files: [FilePart] = []

    /// A text field; nil is left out (as an empty input is not).
    mutating func text(_ name: String, _ value: String?) {
        if let value { fields.append((name, value)) }
    }

    mutating func number(_ name: String, _ value: Int?) { text(name, value.map { String($0) }) }
    mutating func number(_ name: String, _ value: Int64?) { text(name, value.map { String($0) }) }
    /// A decimal as Kotlin writes it ("5.0", "2.5").
    mutating func number(_ name: String, _ value: Double?) { text(name, value.map { String($0) }) }

    /// A checkbox: "on" when ticked, absent when not — what an HTML form sends.
    mutating func check(_ name: String, _ on: Bool) { if on { text(name, "on") } }

    /// The same field several times (a multi-select).
    mutating func texts(_ name: String, _ values: some Sequence<String>) { values.forEach { text(name, $0) } }

    mutating func file(_ name: String, _ file: PickedFile?) {
        guard let file else { return }
        files.append(FilePart(name: name, filename: file.name, mimeType: file.mime, data: file.bytes))
    }

    /// The body. A form with no fields sends one harmless field, as on Android (Retrofit refuses an empty multipart
    /// body, and the server expects a form).
    func build() -> FormBody {
        if fields.isEmpty && files.isEmpty { return FormBody(fields: [("_", "")], files: []) }
        return FormBody(fields: fields, files: files)
    }
}

/// A multipart form body built by [block] (Android's `formOf { … }`).
func formOf(_ block: (inout FormFields) -> Void) -> FormBody {
    var form = FormFields()
    block(&form)
    return form.build()
}

extension APIClient {
    /// Sends a server-action form ([formOf]) with [method] and reads the answer.
    func form<T: Decodable>(_ method: String, _ path: String, _ body: FormBody) async throws -> T {
        try await multipart(path, method: method, fields: body.fields, files: body.files)
    }
}
