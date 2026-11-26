import Observation
import SwiftUI

// Android's WaiverScreens.kt.

let waiverSent = "Your fee waiver request has been submitted successfully!"

/// The waiver page: the student's requests and the courses a new request can name.
struct WaiverPage {
    let requests: [WaiverRequest]
    let courses: [Course]
}

/// Android's WaiversViewModel.
@MainActor
@Observable
final class WaiversModel {
    private(set) var state: Load<WaiverPage> = .loading
    private(set) var sending = false
    private(set) var message: (text: String, ok: Bool)?
    @ObservationIgnored private let repo: AcademyRepository

    init(repo: AcademyRepository) {
        self.repo = repo
        load()
    }

    @discardableResult
    func load() -> Task<Void, Never> {
        Task { await loadNow() }
    }

    private func loadNow() async {
        let repo = self.repo
        // Like the website, every course open for enrollment, not only the ones applied for.
        async let courses = waiverCourseOptions(repo.allCourses().value ?? [])
        switch await repo.waiverRequests() {
        case .success(let requests): state = .ready(WaiverPage(requests: requests, courses: await courses))
        case .failure(let e): state = .failed(e.message)
        }
    }

    /// One request at a time: a second tap before the first is sent is ignored.
    func request(_ body: WaiverRequestBody, onDone: @escaping () -> Void) {
        if sending { return }
        sending = true
        Task {
            switch await repo.requestWaiver(body) {
            case .success:
                message = (waiverSent, true)
                onDone()
                await loadNow()
            case .failure(let e):
                message = (e.message, false)
            }
            sending = false
        }
    }
}

struct WaiversScreen: View {
    @State private var showForm = false

    var body: some View {
        DetailScaffold("Fee Waiver Requests") {
            WithModel({ WaiversModel(repo: $0.repo) }) { model in
                ZStack(alignment: .bottomTrailing) {
                    LoadContent(state: model.state, onRetry: { model.load() }) { page in
                        WaiverList(page: page, message: model.message, showForm: showForm) {
                            WaiverForm(courses: page.courses, sending: model.sending, onCancel: { showForm = false }) { body in
                                model.request(body) { showForm = false }
                            }
                        }
                    }
                    if !showForm {
                        ExtendedFab(icon: .edit, text: "Request Fee Waiver") { showForm = true }
                            .padding(16)
                    }
                }
            }
        }
    }
}

/// Material 3's ExtendedFloatingActionButton.
private struct ExtendedFab: View {
    let icon: Icon
    let text: String
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                icon.image.font(.system(size: 20)).accessibilityHidden(true)
                Text(text).textStyle(Typo.labelLarge)
            }
            .foregroundStyle(Scheme.onPrimaryContainer)
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(Scheme.primaryContainer, in: shape)
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 3)
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle(shape: shape))
    }
}

private struct WaiverList<Form: View>: View {
    let page: WaiverPage
    let message: (text: String, ok: Bool)?
    let showForm: Bool
    @ViewBuilder var form: () -> Form

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Track and manage your fee waiver requests.").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                if let message { Banner(message.text, tone: message.ok ? .success : .danger) }
                // Keyed, so the banner appearing above it (a failed request) doesn't start the form over empty.
                if showForm { form().id("waiver-form") }
                if page.requests.isEmpty {
                    EmptyState(
                        title: "No Fee Waiver Requests",
                        message: "When you submit a fee waiver request during course enrollment or payment, your submitted " +
                            "requests and approved coupon status will appear here."
                    )
                } else {
                    Overline(text: "Past Requests")
                }
                ForEach(page.requests) { WaiverCard(request: $0) }
            }
            .padding(Spacing.screen)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct WaiverCard: View {
    let request: WaiverRequest

    var body: some View {
        let w = request
        let (label, tone) = statusLabel(w.status, kind: .waiver)
        AppCard {
            HStack(spacing: 8) {
                Text(w.course?.title ?? "Course").textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusChip(label, tone: tone)
            }
            Text("\(waiverFeeLabel(w.feeType)) · \(formatDate(w.createdAt))").textStyle(Typo.labelMedium).foregroundStyle(Brand.gold)
            Spacer().frame(height: 6)
            Text("Assigned Coupon").textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
            if let coupon = waiverCouponText(w) {
                Text(coupon).font(.system(.body, design: .monospaced, weight: .bold)).foregroundStyle(Brand.success)
                    .textSelection(.enabled)
            } else {
                Text("—").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurfaceVariant)
            }
        }
    }
}

private struct WaiverForm: View {
    let courses: [Course]
    let sending: Bool
    let onCancel: () -> Void
    let onSend: (WaiverRequestBody) -> Void
    @State private var course = ""
    @State private var fee = defaultWaiverFee
    @State private var category = waiverReasons[0]
    @State private var details = ""

    var body: some View {
        let other = category == waiverReasonOther
        AppCard {
            Text("Request Fee Waiver").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
            Text("If you are unable to pay the course fees, you can request a fee waiver here. The administration will review your request and may provide you with a special coupon code.")
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            Spacer().frame(height: 10)
            Dropdown(value: courses.first { $0.id == course }?.title ?? "Select a course...", options: courses.map(\.title), label: "Course") {
                course = courses[$0].id
            }
            Spacer().frame(height: 10)
            Dropdown(value: fee.label, options: WaiverFee.allCases.map(\.label), label: "Fee Type") { fee = WaiverFee.allCases[$0] }
            Spacer().frame(height: 10)
            Dropdown(value: category, options: waiverReasons, label: "Reason for Waiver") { category = waiverReasons[$0] }
            Spacer().frame(height: 10)
            OutlinedField(
                label: other ? "Please specify reason" : "Additional details (optional)",
                text: Binding(get: { details }, set: { details = $0.jsPrefix(waiverDetailsMax) }),
                placeholder: other ? "Describe your reason..." : "Add any additional context for your request (optional)...",
                supporting: "\(details.jsLength)/\(waiverDetailsMax)",
                lines: 3...3
            )
            Spacer().frame(height: 10)
            WeightedRow(weights: [1, 2], spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancel").textStyle(Typo.labelLarge).foregroundStyle(Scheme.primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(shape: Capsule()))
                PrimaryButton(
                    "Submit Request",
                    enabled: waiverFormReady(courseId: course, category: category, details: details),
                    loading: sending
                ) {
                    onSend(waiverRequestBody(courseId: course, fee: fee, category: category, details: details))
                }
            }
        }
    }
}
