import Foundation

// The website's words for a student's courses: /profile/courses and its attendance, grades and announcements pages
// (Android's CourseWords.kt).

/// "Roll No: 05": the website pads roll numbers to two digits (services/roll-numbers.ts formatRollNumber).
func rollNumberLabel(_ rollNumber: Int) -> String {
    let digits = String(rollNumber)
    return "Roll No: " + String(repeating: "0", count: max(0, 2 - digits.count)) + digits
}

/// The lines under a course on My courses, as the website's course card shows them for its status.
func enrollmentNotes(_ e: Enrollment) -> [String] {
    var notes: [String] = []
    switch e.status {
    case EnrollmentStatus.pendingApproval: notes.append("Awaiting enrollment approval by the academy.")
    case EnrollmentStatus.awaitingEnrollmentFee: notes.append("Pay the enrollment fee to complete your application.")
    case EnrollmentStatus.rejected:
        notes.append("This request was not approved\(e.rejectedAt.map { " on \(formatDate($0))" } ?? ""). Contact the academy if you have questions.")
    case EnrollmentStatus.active:
        if (e.course?.monthlyFeeInrPaise ?? 0) <= 0 { notes.append("No fee required") }
    default: break
    }
    if let completed = e.completedAt { notes.append("Completed \(formatDate(completed))") }
    let waiting = e.status == EnrollmentStatus.awaitingEnrollmentFee || e.status == EnrollmentStatus.pendingApproval
    if !EnrollmentStatus.opensLearn(e.status), !waiting, !e.createdAt.isEmpty {
        notes.append("Requested \(formatDate(e.createdAt))")
    }
    return notes
}

/// The grade report's totals (components/grades/StudentGradeReport.tsx): ungraded exams are left out.
struct StudentGradeSummary: Equatable {
    let exams: Int
    let obtained: Double
    let max: Double
    let percentage: Int
}

func gradeSummary(_ grades: [GradeEntry]) -> StudentGradeSummary {
    let graded = grades.filter { $0.marksObtained != nil }
    let obtained = graded.reduce(0) { $0 + ($1.marksObtained ?? 0) }
    let max = graded.reduce(0) { $0 + $1.maxMarks }
    let percentage = max == 0 ? 0 : Int((obtained / max * 100).rounded())
    return StudentGradeSummary(exams: graded.count, obtained: obtained, max: max, percentage: percentage)
}

/// An exam's marks: "—" when not graded; a zero is noted as "recorded as 0", as on the website.
func gradeMarks(_ g: GradeEntry) -> (marks: String, note: String?) {
    guard let marks = g.marksObtained else { return ("—", nil) }
    return ("\(formatMarks(marks)) / \(formatMarks(g.maxMarks))", marks == 0 ? "recorded as 0" : nil)
}

func formatMarks(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.2f", value)
}
