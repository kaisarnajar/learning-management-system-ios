import Foundation

/*
 * Money, dates and words, ported from Android's Format.kt.
 */

private let inr: NumberFormatter = {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_IN")
    f.numberStyle = .decimal
    f.minimumFractionDigits = 0
    f.maximumFractionDigits = 2
    return f
}()

private let inrPaise: NumberFormatter = {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_IN")
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f
}()

/// ₹ from paise in Indian grouping: 34900 → "₹349", 12350 → "₹123.50", -158475350 → "-₹15,84,753.50". With [exact]
/// the paise always show ("₹50.00"), as charge tables print them. Worked out in exact decimals, not by dividing a Double.
func formatInr(_ paise: Int64, exact: Bool = false) -> String {
    let amount = Decimal(paise.magnitude) / 100
    let whole = paise.magnitude % 100 == 0
    let text = ((whole && !exact) ? inr : inrPaise).string(from: amount as NSDecimalNumber) ?? "\(amount)"
    return (paise < 0 ? "-₹" : "₹") + text
}

/// ₹ from paise: 34900 → "₹349", 12350 → "₹123.50".
func rupees(_ paise: Int) -> String { formatInr(Int64(paise)) }

/// The academy's time zone: "today", a fee's month and a class date are the academy's, not the phone's.
let academyZone = TimeZone(identifier: "Asia/Kolkata")!

/// A Gregorian calendar in the academy's time zone.
var academyCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = academyZone
    return c
}

/// Today's date at the academy (year, month, day), whatever time zone the phone is set to.
func academyToday(now: Date = Date()) -> DateComponents {
    academyCalendar.dateComponents([.year, .month, .day], from: now)
}

private func formatter(_ pattern: String, zone: TimeZone = academyZone) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = zone
    f.dateFormat = pattern
    // English month names and AM/PM, as Android's Locale.ENGLISH.
    f.amSymbol = "AM"
    f.pmSymbol = "PM"
    return f
}

private let dayFormat = formatter("d MMM yyyy")
private let dayFormatUTC = formatter("d MMM yyyy", zone: TimeZone(identifier: "UTC")!)
private let dayTimeFormat = formatter("d MMM yyyy, h:mm a")
private let localDateTime = formatter("yyyy-MM-dd'T'HH:mm:ss")
private let localDateTimeMinutes = formatter("yyyy-MM-dd'T'HH:mm")
private let localDate = formatter("yyyy-MM-dd")
nonisolated(unsafe) private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
nonisolated(unsafe) private let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

/// An instant from the API's date strings: ISO with an offset or Z (with or without fractions), a bare date (the
/// academy's midnight), or a date and time without a zone (academy time).
func parseDate(_ value: String?) -> Date? {
    guard let value = value?.trimmed, !value.isEmpty else { return nil }
    if let d = isoFractional.date(from: value) ?? iso.date(from: value) { return d }
    if value.count == 10, let d = localDate.date(from: value) { return d }
    // A date and time without a zone ("2026-11-16T10:00:00") is academy time; it used to lose its time of day.
    let noFraction = value.components(separatedBy: ".").first ?? value
    if let d = localDateTime.date(from: noFraction) ?? localDateTimeMinutes.date(from: noFraction) { return d }
    if value.count > 10, Array(value)[10] == "T", let d = localDate.date(from: String(value.prefix(10))) { return d }
    return nil
}

/// "16 Nov 2026"; free text (an event date typed by the admin) is shown as written.
func formatDate(_ value: String?) -> String {
    guard let date = parseDate(value) else { return value ?? "" }
    return dayFormat.string(from: date)
}

/// Calendar-only fields stored as UTC midnight: format in UTC so the day never shifts.
func formatCalendarDate(_ value: String?) -> String {
    guard let value else { return "" }
    let utcDate = formatter("yyyy-MM-dd", zone: TimeZone(identifier: "UTC")!)
    guard let d = utcDate.date(from: String(value.prefix(10))) else { return value }
    return dayFormatUTC.string(from: d)
}

func formatDateTime(_ value: String?) -> String {
    guard let date = parseDate(value) else { return "" }
    return dayTimeFormat.string(from: date)
}

/// "2h ago", "3 days ago", or a date for older items.
func relativeTime(_ value: String?, now: Date = Date()) -> String {
    guard let time = parseDate(value) else { return "" }
    let seconds = Int(now.timeIntervalSince(time))
    switch seconds {
    case ..<60: return "just now"
    case ..<3600: return "\(seconds / 60) min ago"
    case ..<86_400: return "\(seconds / 3600) h ago"
    case ..<(7 * 86_400): return "\(countOf(seconds / 86_400, "day")) ago"
    default: return dayFormat.string(from: time)
    }
}

func feeFrequencySuffix(_ frequency: String?) -> String {
    switch frequency {
    case "MONTHLY", nil: "/ month"
    case "EVERY_3_MONTHS": "/ 3 months"
    case "EVERY_6_MONTHS": "/ 6 months"
    case "YEARLY": "/ year"
    case "ONE_TIME": "one time"
    default: ""
    }
}

func titleCase(_ value: String) -> String {
    value.lowercased().split(whereSeparator: { $0 == "_" || $0 == " " }).map { word in
        word.prefix(1).uppercased() + word.dropFirst()
    }.joined(separator: " ")
}

/// Labels the web app shows for announcement categories.
func announcementCategory(_ value: String) -> String {
    switch value {
    case "EXAMS_TESTS": "Exams & Tests"
    case "ASSIGNMENTS_HOMEWORK": "Assignments & Homework"
    case "STUDY_MATERIALS": "Study Materials"
    case "CLASS_SCHEDULE": "Class Schedule"
    case "COURSE_ANNOUNCEMENT": "Course Announcement"
    case "GENERAL_NOTICE": "General Notice"
    default: titleCase(value)
    }
}

/// "1 comment", "3 comments".
func countOf(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
}

// MARK: - months (Fees.kt)

/// A calendar month at the academy (Android's LocalDate set to the 1st of a month).
struct YearMonth: Hashable, Sendable, Comparable, Codable {
    var year: Int
    var month: Int

    static func current(now: Date = Date()) -> YearMonth {
        let t = academyToday(now: now)
        return YearMonth(year: t.year!, month: t.month!)
    }

    var monthName: String { DateFormatter().monthSymbols.indices.contains(month - 1) ? englishMonths[month - 1] : "" }

    func plusMonths(_ n: Int) -> YearMonth {
        let index = year * 12 + (month - 1) + n
        return YearMonth(year: index / 12, month: index % 12 + 1)
    }

    static func < (a: YearMonth, b: YearMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }
}

let englishMonths = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

/// "November 2026": the period a monthly fee is for.
func feePeriod(_ month: YearMonth) -> String { "\(englishMonths[month.month - 1]) \(month.year)" }

/// The label the website gives a monthly fee payment ("Monthly fee — November 2026"; its buildMonthlyFeeLabel).
func monthlyFeeLabel(_ month: YearMonth) -> String { "Monthly fee — \(feePeriod(month))" }

/// Whether [enrollment]'s fee for [today]'s month is still to pay: an active course billed monthly, with no payment for
/// that month that the academy hasn't refused. A payment is matched by the label the website gives it, in full.
func monthlyFeeDue(_ enrollment: Enrollment, _ submissions: [PaymentSubmission], today: YearMonth = .current()) -> Bool {
    guard let course = enrollment.course else { return false }
    if enrollment.status != EnrollmentStatus.active || course.monthlyFeeInrPaise <= 0 || (course.feeFrequency ?? "MONTHLY") != "MONTHLY" { return false }
    let label = monthlyFeeLabel(today)
    return !submissions.contains {
        $0.courseId == enrollment.courseId && $0.paymentType != "enrollment" &&
            ($0.label == label || $0.label == feePeriod(today)) && // the second: labels from before the website's format
            $0.status != "rejected" && $0.status != "declined"
    }
}

/// A course's fee as cards and the course page show it: "₹500 / month", "₹2,000 one time", or "Free".
func courseFeeText(_ course: Course) -> String {
    course.monthlyFeeInrPaise > 0 ? "\(rupees(course.monthlyFeeInrPaise)) \(feeFrequencySuffix(course.feeFrequency))" : "Free"
}

// MARK: - links (Links.kt)

/// Where a link found in academy content should go.
enum LinkTarget: Equatable {
    /// A page of the academy's own site: open the matching screen ([path] like "/blog/abc").
    case inApp(String)
    /// Anywhere else (another site, mail, phone): hand it to the phone.
    case outside(String)
}

/// Relative links and links to the academy's own host stay in the app; the rest go outside.
func linkTarget(_ href: String, baseUrl: String = CurrentEnvironment.baseUrl) -> LinkTarget {
    let trimmed = href.trimmed
    // A protocol-relative link ("//host/x") means https here: there is no page whose protocol it could follow.
    if trimmed.hasPrefix("//") { return linkTarget("https:" + trimmed, baseUrl: baseUrl) }
    if trimmed.hasPrefix("/") { return .inApp(trimmed) }
    guard let url = URLComponents(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
          let host = url.host, !host.isEmpty else { return .outside(trimmed) }
    let base = URLComponents(string: baseUrl)
    let bare = { (h: String) in h.lowercased().hasPrefix("www.") ? String(h.dropFirst(4)).lowercased() : h.lowercased() }
    if let baseHost = base?.host, bare(host) == bare(baseHost) {
        let path = url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath
        return .inApp(path + (url.percentEncodedQuery.map { "?" + $0 } ?? ""))
    }
    return .outside(url.string ?? trimmed)
}
