import Observation
import SwiftUI

struct PayState {
    var loading = true
    var error: String?
    var quote: PaymentQuote?
    var settings: PaymentSettings?
    var couponId: String?
    var month: Int = YearMonth.current().month
    var year: String = String(YearMonth.current().year)
    var settingsError: String?
    var submitting = false
    var submitError: String?
    var done = false

    var amountPaise: Int {
        quote?.coupons.first { $0.id == couponId }?.amountPaise ?? (quote?.baseAmountPaise ?? 0)
    }
}

/// The choices made on the pay screen, kept apart from the screen (Android's SavedStateHandle): paying sends the student
/// to their UPI app, and they must come back to the same waiver, month and year, or the transaction id they paid with
/// would be submitted for another month or amount.
@MainActor
final class PaySavedState {
    private(set) var values: [String: any Sendable] = [:]

    init(_ values: [String: any Sendable] = [:]) { self.values = values }

    subscript(key: String) -> (any Sendable)? {
        get { values[key] }
        set { values[key] = newValue }
    }

    func contains(_ key: String) -> Bool { values[key] != nil }
}

/// The fee payment flow (Android's PayViewModel).
@MainActor
@Observable
final class PayModel {
    static let couponKey = "couponId"
    static let monthKey = "month"
    static let yearKey = "year"

    let courseId: String
    let type: String
    private(set) var state: PayState

    @ObservationIgnored private let repo: AcademyRepository
    @ObservationIgnored let saved: PaySavedState

    init(repo: AcademyRepository, courseId: String, type: String, saved: PaySavedState = PaySavedState()) {
        self.repo = repo
        self.courseId = courseId
        self.type = type
        self.saved = saved
        let today = YearMonth.current()
        state = PayState(
            couponId: saved[Self.couponKey] as? String,
            month: saved[Self.monthKey] as? Int ?? today.month,
            year: saved[Self.yearKey] as? String ?? String(today.year)
        )
        load()
    }

    @discardableResult
    func load() -> Task<Void, Never> {
        state.loading = true
        state.error = nil
        let repo = repo, courseId = courseId, type = type
        return Task {
            async let quoteResult = repo.paymentQuote(courseId: courseId, type: type)
            async let settingsResult = repo.paymentSettings()
            switch await quoteResult {
            case .success(let quote):
                let settings = await settingsResult
                // A waiver chosen before the app was killed may be used up or withdrawn since: sending it anyway
                // would have the payment refused, so the standard fee is selected instead.
                let couponId = state.couponId.flatMap { id in quote.coupons.contains { $0.id == id } ? id : nil }
                if couponId == nil { saved[Self.couponKey] = nil }
                let thisYear = String(YearMonth.current().year)
                state.loading = false
                state.quote = quote
                state.couponId = couponId
                state.settings = settings.value
                state.settingsError = settings.error?.message
                if !saved.contains(Self.yearKey) {
                    state.year = quote.yearOptions.first { $0 == thisYear } ?? quote.yearOptions.first ?? state.year
                }
            case .failure(let e):
                state.loading = false
                state.error = e.message
            }
        }
    }

    /// Fetches the academy's UPI and bank details again (after they failed to load).
    @discardableResult
    func reloadSettings() -> Task<Void, Never> {
        state.settingsError = nil
        let repo = repo
        return Task {
            let r = await repo.paymentSettings()
            state.settings = r.value ?? state.settings
            state.settingsError = r.error?.message
        }
    }

    func selectCoupon(_ id: String?) { saved[Self.couponKey] = id; state.couponId = id }
    func selectMonth(_ m: Int) { saved[Self.monthKey] = m; state.month = m }
    func selectYear(_ y: String) { saved[Self.yearKey] = y; state.year = y }

    /// One submission per payment: a second tap (even in the same frame) or a tap after success is ignored.
    @discardableResult
    func submit(method: String, reference: String, screenshot: (Data, String)?) -> Task<Void, Never>? {
        let s = state
        guard !s.submitting, !s.done, let quote = s.quote else { return nil }
        state.submitting = true
        state.submitError = nil
        let fields = submissionFields(s, quote: quote, method: method, reference: reference)
        let repo = repo
        return Task {
            switch await repo.submitPayment(fields: fields, screenshot: screenshot) {
            case .success: state.submitting = false; state.done = true
            case .failure(let e): state.submitting = false; state.submitError = e.message
            }
        }
    }

    private func submissionFields(_ s: PayState, quote: PaymentQuote, method: String, reference: String) -> [(String, String)] {
        var fields: [(String, String)] = [
            ("courseId", courseId),
            ("paymentType", type == "enrollment" ? "enrollment" : "monthly"),
        ]
        if type == "course" {
            fields.append(("paymentMonth", quote.oneTimeFee ? "01" : String(format: "%02d", s.month)))
            fields.append(("paymentYear", s.year))
        }
        if s.amountPaise > 0 {
            fields.append(("paymentMethod", method))
            fields.append(("upiTransactionId", reference.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        fields.append(("couponId", s.couponId ?? "none"))
        fields.append(("expectedAmountPaise", String(s.amountPaise)))
        return fields
    }
}

struct PayScreen: View {
    let courseId: String
    let type: String
    let title: String
    var body: some View {
        WithModel({ PayModel(repo: $0.repo, courseId: courseId, type: type) }) { model in
            PayContent(model: model, courseTitle: title)
        }
    }
}

private struct PayContent: View {
    let model: PayModel
    let courseTitle: String
    @Environment(Navigator.self) private var nav

    var body: some View {
        let heading = model.type == "enrollment" ? "Enrollment fee" : "Course fee"
        let state = model.state
        DetailScaffold(heading) {
            if state.loading {
                LoadingBox()
            } else if let error = state.error {
                ErrorState(message: error) { model.load() }
            } else if state.done {
                MessageState(icon: .checkCircle, title: paymentSubmittedTitle, message: paymentSubmittedBody, action: "Done") { nav.pop() }
            } else if state.quote?.canPay == false {
                MessageState(icon: .info, title: "Payment not available", message: state.quote?.reason, action: "Back") { nav.pop() }
            } else {
                PayFlow(model: model, courseTitle: courseTitle, heading: heading)
            }
        }
    }
}

private struct PayFlow: View {
    let model: PayModel
    let courseTitle: String
    let heading: String
    @State private var method = "upi"
    @State private var reference = ""
    @State private var proof = ProofImagePicker()

    var body: some View {
        let state = model.state
        let quote = state.quote!
        let free = state.amountPaise == 0
        let settings = state.settings

        ScreenColumn(spacing: 16) {
            // ---- step 1: amount
            StepHeader(number: 1, title: "Amount")
            AppCard {
                Text(courseTitle).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                Text(heading + (quote.feeFrequencyLabel.map { " · \($0)" } ?? ""))
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                Spacer().frame(height: 12)
                Text(rupees(state.amountPaise)).textStyle(Typo.displaySmall).foregroundStyle(Scheme.primary)
                if state.couponId != nil {
                    Text("Standard fee \(rupees(quote.baseAmountPaise))").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                if !quote.coupons.isEmpty {
                    Spacer().frame(height: 14)
                    Overline(text: "Available Coupons & Fee Waivers")
                    ChoiceRow(label: "\(noCoupon) · \(rupees(quote.baseAmountPaise))", selected: state.couponId == nil) { model.selectCoupon(nil) }
                    ForEach(quote.coupons) { c in
                        ChoiceRow(label: "\(c.code) · \(c.percentage)% off · \(rupees(c.amountPaise))", selected: state.couponId == c.id) {
                            model.selectCoupon(c.id)
                        }
                    }
                }
                if model.type == "course" && !quote.oneTimeFee {
                    Spacer().frame(height: 14)
                    WeightedRow(weights: [1.4, 1], spacing: 10) {
                        Dropdown(value: englishMonths[state.month - 1], options: englishMonths, label: "Starting Month") { model.selectMonth($0 + 1) }
                        Dropdown(value: state.year, options: quote.yearOptions, label: "Starting Year") { model.selectYear(quote.yearOptions[$0]) }
                    }
                }
            }

            if !free {
                // ---- step 2: pay
                StepHeader(number: 2, title: "Pay")
                PaymentDetailsError(message: state.settingsError) { model.reloadSettings() }
                PayWithUpiButton(settings: settings, amountPaise: state.amountPaise, note: "\(heading) - \(courseTitle)")
                PaymentDetailsCard(settings: settings, amountPaise: state.amountPaise, note: feePaymentNote(model.type, courseTitle, quote.feeFrequencyLabel))

                // ---- step 3: confirm
                StepHeader(number: 3, title: "Confirm")
                PaymentConfirmFields(settings: settings, method: $method, reference: $reference, proof: proof)
            } else {
                Banner("This fee is fully waived. Submit it for the academy to confirm.", tone: .success)
            }

            if let error = state.submitError { Banner(error, tone: .danger) }
            PrimaryButton(paySubmitLabel(model.type, free: free), enabled: canSubmitPayment(free: free, reference: reference), loading: state.submitting) {
                model.submit(method: method, reference: reference, screenshot: proof.image?.upload)
            }
            Spacer().frame(height: 24)
        }
    }
}

private struct StepHeader: View {
    let number: Int
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)").textStyle(Typo.labelLarge).foregroundStyle(Scheme.onPrimary)
                .frame(width: 28, height: 28)
                .background(Scheme.primary, in: Circle())
                .accessibilityHidden(true)
            Text(title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A radio button and its label, the whole row tappable (Android's ChoiceRow).
private struct ChoiceRow: View {
    let label: String
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 0) {
                ZStack {
                    Circle().strokeBorder(selected ? Scheme.primary : Scheme.onSurfaceVariant, lineWidth: 2).frame(width: 20, height: 20)
                    if selected { Circle().fill(Scheme.primary).frame(width: 10, height: 10) }
                }
                .frame(width: 48, height: 48)
                Text(label).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(shape: RoundedRectangle(cornerRadius: Radius.input)))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - wording

/// The website's toast on the payments page after any fee submission, waivers included, split in two lines.
let paymentSubmittedTitle = "Payment submitted."
let paymentSubmittedBody = "The academy will verify it shortly."

/// The website's CouponSelector option for paying the full fee.
let noCoupon = "Do not use any coupon"

private let noteMax = 80

/// The website's submit button wording (EnrollmentPaymentForm and MonthlyPaymentForm).
func paySubmitLabel(_ type: String, free: Bool) -> String {
    switch (type == "enrollment", free) {
    case (true, true): "Claim Fee Waiver & Enroll"
    case (true, false): "Submit enrollment fee for verification"
    case (false, true): "Claim Fee Waiver"
    case (false, false): "Submit fee payment for verification"
    }
}

/// The website only requires the transaction reference to be filled in; a waived fee needs none.
func canSubmitPayment(free: Bool, reference: String) -> Bool {
    free || !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// The UPI note the website's pay forms put in the QR code.
func feePaymentNote(_ type: String, _ courseTitle: String, _ feeFrequencyLabel: String?) -> String {
    let note = type == "enrollment" ? "\(courseTitle) enrollment" : "\(courseTitle) — \(feeFrequencyLabel ?? "Monthly")"
    return String(note.prefix(noteMax))
}
