import Foundation

/// The website's preset reasons (components/profile/WaiverRequestModal.tsx), in its order (Android's WaiverRules.kt).
let waiverReasons = [
    "Financial hardship",
    "Student / Currently studying",
    "Unemployed / Job seeking",
    "Single parent / Primary caregiver",
    "Orphan / Loss of family breadwinner",
    "Medical expenses / Health condition",
    "Disaster / Emergency relief",
    "Madrasa / Full-time Islamic student",
    "Revert / New Muslim support",
    "Senior citizen / Retired with fixed income",
    "Other",
]

let waiverReasonOther = "Other"

/// The website's limit on the details box (maxLength on the textarea).
let waiverDetailsMax = 900

/// Which fee a waiver is for; the website offers these two, course fee first selected.
enum WaiverFee: CaseIterable {
    case enrollment, course

    var value: String {
        switch self {
        case .enrollment: "enrollment"
        case .course: "course"
        }
    }

    var label: String {
        switch self {
        case .enrollment: "Enrollment Fee"
        case .course: "Course Fee"
        }
    }
}

let defaultWaiverFee = WaiverFee.course

private let waiverOpenStatuses: Set<String> = ["PUBLISHED", "ONGOING"]

/// Courses a waiver can be asked for: those open for enrollment, by title, as the website lists them.
func waiverCourseOptions(_ courses: [Course]) -> [Course] {
    var seen = Set<String>()
    let open = courses.filter { waiverOpenStatuses.contains($0.status) && seen.insert($0.id).inserted }
    return open.enumerated().sorted { a, b in
        let order = a.element.title.caseInsensitiveCompare(b.element.title)
        return order == .orderedSame ? a.offset < b.offset : order == .orderedAscending
    }.map(\.element)
}

/// The reason the website sends: the preset, then " - details" when details were typed.
func waiverReason(_ category: String, _ details: String) -> String {
    let extra = details.trimmed
    return extra.isEmpty ? category : "\(category) - \(extra)"
}

/// The details box is required only for "Other", as on the website.
func waiverFormReady(courseId: String, category: String, details: String) -> Bool {
    !courseId.trimmed.isEmpty && (category != waiverReasonOther || !details.trimmed.isEmpty)
}

func waiverRequestBody(courseId: String, fee: WaiverFee, category: String, details: String) -> WaiverRequestBody {
    WaiverRequestBody(courseId: courseId, feeType: fee.value, reason: waiverReason(category, details))
}

/// The fee-type column of the website's table (services/waiver-requests.ts waiverFeeTypeLabel).
func waiverFeeLabel(_ feeType: String?) -> String {
    switch feeType?.uppercased() {
    case "ENROLLMENT": "Enrollment Fee"
    case "COURSE": "Course Fee"
    default: "Both"
    }
}

/// The "Assigned Coupon" column: every issued code and the discount, or nil for the website's dash.
func waiverCouponText(_ request: WaiverRequest) -> String? {
    guard let coupon = request.coupon else { return nil }
    let codes = request.couponCodes.isEmpty ? [coupon.code] : request.couponCodes
    return "\(codes.joined(separator: "  ")) (\(coupon.percentage)% OFF)"
}
