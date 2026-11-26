import Foundation

/*
 * Lenient decoding, as Android's Json { coerceInputValues = true }: a field with a default that is missing, null or of
 * the wrong type decodes as its default instead of failing the whole answer. So the server can grow without breaking
 * installed apps.
 *
 *     @Default<Empty.Text> var description: String
 *     @Default<Zero> var priceInrPaise: Int
 */

protocol DefaultValue {
    associatedtype Value: Codable & Sendable & Hashable
    static var defaultValue: Value { get }
}

@propertyWrapper
struct Default<D: DefaultValue>: Codable, Sendable, Hashable {
    var wrappedValue: D.Value

    init(wrappedValue: D.Value) { self.wrappedValue = wrappedValue }
    init() { wrappedValue = D.defaultValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = (try? container.decode(D.Value.self)) ?? D.defaultValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension KeyedDecodingContainer {
    /// A missing key gives the default (the synthesized init would otherwise throw keyNotFound).
    func decode<D>(_ type: Default<D>.Type, forKey key: Key) throws -> Default<D> {
        (try? decodeIfPresent(type, forKey: key)) ?? Default()
    }
}

// MARK: - The defaults used by the models

enum Empty {
    enum Text: DefaultValue { static var defaultValue: String { "" } }
    enum List<T: Codable & Sendable & Hashable>: DefaultValue { static var defaultValue: [T] { [] } }
}
enum Zero: DefaultValue { static var defaultValue: Int { 0 } }
enum ZeroDouble: DefaultValue { static var defaultValue: Double { 0 } }
enum False: DefaultValue { static var defaultValue: Bool { false } }
enum True: DefaultValue { static var defaultValue: Bool { true } }
enum One: DefaultValue { static var defaultValue: Int { 1 } }
enum Five: DefaultValue { static var defaultValue: Int { 5 } }
enum Twenty: DefaultValue { static var defaultValue: Int { 20 } }
enum Four: DefaultValue { static var defaultValue: Int { 4 } }
enum Fifteen: DefaultValue { static var defaultValue: Int { 15 } }
enum Hour: DefaultValue { static var defaultValue: Int { 3600 } }
enum UserRole: DefaultValue { static var defaultValue: String { "USER" } }
enum Published: DefaultValue { static var defaultValue: String { "PUBLISHED" } }
enum Available: DefaultValue { static var defaultValue: String { "AVAILABLE" } }
enum Quran: DefaultValue { static var defaultValue: String { "QURAN" } }
enum PendingUpper: DefaultValue { static var defaultValue: String { "PENDING" } }
enum CountryIN: DefaultValue { static var defaultValue: String { "IN" } }

/// A nested object with its own defaults ("brand": {...} missing → Brand()).
enum Fallback<T: Codable & Sendable & Hashable & Initable>: DefaultValue { static var defaultValue: T { T() } }

/// Types that have an all-defaults value (Kotlin's `= Brand()`).
protocol Initable { init() }
