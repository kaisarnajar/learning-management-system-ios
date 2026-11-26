import Foundation

/*
 * The extra defaults the staff models use (see Data/Remote/Defaults.swift for how @Default works):
 *
 *     @Default<ZeroLong> var incomeTotalPaise: Int64 = 0
 *     @Default<Dash> var rollNumberLabel: String = "—"
 */

enum ZeroLong: DefaultValue { static var defaultValue: Int64 { 0 } }
enum Six: DefaultValue { static var defaultValue: Int { 6 } }
enum Ten: DefaultValue { static var defaultValue: Int { 10 } }
/// "—", the website's placeholder for a missing roll number.
enum Dash: DefaultValue { static var defaultValue: String { "—" } }
enum Monthly: DefaultValue { static var defaultValue: String { "MONTHLY" } }
enum Beginner: DefaultValue { static var defaultValue: String { "Beginner" } }
enum DefaultCouponType: DefaultValue { static var defaultValue: String { "DEFAULT" } }
enum ApplyToBoth: DefaultValue { static var defaultValue: String { "BOTH" } }
enum ThisMonth: DefaultValue { static var defaultValue: String { "this_month" } }
enum IncomeTab: DefaultValue { static var defaultValue: String { "income" } }
enum SalesView: DefaultValue { static var defaultValue: String { "sales" } }
enum PendingLower: DefaultValue { static var defaultValue: String { "pending" } }
enum SystemActor: DefaultValue { static var defaultValue: String { "system" } }
/// The library's reading levels when the server doesn't send them.
enum LibraryLevels: DefaultValue { static var defaultValue: [String] { ["Beginner", "Intermediate", "Advanced"] } }
enum EmptyCounts: DefaultValue { static var defaultValue: [String: Int] { [:] } }

extension KeyedDecodingContainer {
    /// The value at [key], or [fallback] when it is missing, null or of another type (for Kotlin defaults that name
    /// another field, such as `dateLabel: String = date`).
    func lenient<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}
