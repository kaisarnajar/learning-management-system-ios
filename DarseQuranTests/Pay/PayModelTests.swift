import XCTest
@testable import DarseQuran

/// Ported from Android's PayViewModelTest (SavedStateHandle → PaySavedState).
@MainActor
final class PayModelTests: XCTestCase {
    private var server: StubServer!
    private var backend: StubBackend!
    private let submissions = Box(0)
    private let settingsFail = Box(false)
    private let oneTimeFee = Box(false)
    private let lastSubmission = Box(Data())

    override func setUp() async throws {
        server = StubServer()
        let (submissions, settingsFail, oneTimeFee, lastSubmission) = (submissions, settingsFail, oneTimeFee, lastSubmission)
        server.handler = { request in
            switch request.path {
            case "/api/v1/payment-settings":
                return settingsFail.value ? .json("{}", status: 503) : .json(#"{"settings":{"upiId":"academy@upi"}}"#)
            case "/api/v1/payments/quote":
                return .json(#"""
                {"courseId":"c1","type":"course","canPay":true,"baseAmountPaise":50000,"yearOptions":["2026"],
                 "oneTimeFee":\#(oneTimeFee.value),"coupons":[
                 {"id":"waiver-50","code":"HALF","percentage":50,"amountPaise":25000},
                 {"id":"waiver-100","code":"FULL","percentage":100,"amountPaise":0}]}
                """#)
            case "/api/v1/payments/submit":
                submissions.update { $0 += 1 }
                lastSubmission.value = request.body
                Thread.sleep(forTimeInterval: 0.2)
                return .json(#"{"success":true}"#)
            default:
                return .json("{}", status: 404)
            }
        }
        CurrentEnvironment.testBaseUrl = server.baseUrl
        backend = StubBackend(server)
    }

    override func tearDown() async throws {
        CurrentEnvironment.testBaseUrl = nil
        server = nil
        backend = nil
    }

    private func model(_ type: String = "course", saved: PaySavedState = PaySavedState()) async -> PayModel {
        let vm = PayModel(repo: backend.repo, courseId: "c1", type: type, saved: saved)
        await waitUntil { vm.state.quote != nil }
        return vm
    }

    func testADoubleTapSubmitsOnePayment() async {
        let vm = await model()
        vm.submit(method: "UPI", reference: "123456789012", screenshot: nil)
        vm.submit(method: "UPI", reference: "123456789012", screenshot: nil)
        await waitUntil { vm.state.done }
        vm.submit(method: "UPI", reference: "123456789012", screenshot: nil) // a tap after success
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(1, submissions.value)
    }

    func testChoicesComeBackAfterTheAppWasKilled() async {
        // What the screen is handed back, from the choices made before paying.
        let vm = await model(saved: PaySavedState(["couponId": "waiver-50", "month": 3, "year": "2025"]))
        XCTAssertEqual("waiver-50", vm.state.couponId)
        XCTAssertEqual(3, vm.state.month)
        XCTAssertEqual("2025", vm.state.year) // the quote's year options don't override a year already chosen
    }

    func testChoicesAreRecorded() {
        let saved = PaySavedState()
        let vm = PayModel(repo: backend.repo, courseId: "c1", type: "course", saved: saved)
        vm.selectCoupon("waiver-50"); vm.selectMonth(7); vm.selectYear("2026")
        XCTAssertEqual("waiver-50", saved["couponId"] as? String)
        XCTAssertEqual(7, saved["month"] as? Int)
        XCTAssertEqual("2026", saved["year"] as? String)
    }

    func testChoicesSurviveTheAppBeingEndedAndAreForgottenAfterPaying() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pay-saved-test"))
        defaults.removePersistentDomain(forName: "pay-saved-test")
        let key = PaySavedState.key(courseId: "c1", type: "course")
        let before = PaySavedState(defaultsKey: key, defaults: defaults)
        before["couponId"] = "waiver-50"; before["month"] = 3; before["year"] = "2025"
        // The app is started again: a new pay screen for the same payment reads the choices back.
        let after = PaySavedState(defaultsKey: key, defaults: defaults)
        XCTAssertEqual("waiver-50", after["couponId"] as? String)
        XCTAssertEqual(3, after["month"] as? Int)
        XCTAssertEqual("2025", after["year"] as? String)
        XCTAssertNil(PaySavedState(defaultsKey: PaySavedState.key(courseId: "c2", type: "course"), defaults: defaults)["month"])
        after.clear()
        XCTAssertNil(PaySavedState(defaultsKey: key, defaults: defaults)["couponId"])
    }

    func testPaymentDetailsThatFailToLoadAreReportedAndCanBeRetried() async {
        settingsFail.value = true
        let vm = await model()
        XCTAssertEqual("The academy's server had a problem. Please try again.", vm.state.settingsError)
        settingsFail.value = false
        vm.reloadSettings()
        await waitUntil { vm.state.settings != nil }
        XCTAssertNil(vm.state.settingsError)
        XCTAssertEqual("academy@upi", vm.state.settings?.upiId)
    }

    /// The form fields of the last submission (multipart: name, headers, a blank line, then the value).
    private func fields() -> [String: String] {
        let text = String(decoding: lastSubmission.value, as: UTF8.self)
        let regex = try! NSRegularExpression(pattern: "name=\"([^\"]+)\"\r\n(?:[^\r]+\r\n)*\r\n([^\r]*)\r\n")
        var out: [String: String] = [:]
        for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            out[String(text[Range(m.range(at: 1), in: text)!])] = String(text[Range(m.range(at: 2), in: text)!])
        }
        return out
    }

    private func submitted(_ vm: PayModel) async -> [String: String] {
        vm.submit(method: "upi", reference: " 123456789012 ", screenshot: nil)
        await waitUntil { vm.state.done }
        return fields()
    }

    func testAMonthlyFeeWithAWaiverSendsTheWaivedAmountAndThePaddedMonth() async {
        let vm = await model()
        vm.selectCoupon("waiver-50"); vm.selectMonth(7); vm.selectYear("2026")
        let sent = await submitted(vm)
        XCTAssertEqual(
            [
                "courseId": "c1", "paymentType": "monthly", "paymentMonth": "07", "paymentYear": "2026",
                "paymentMethod": "upi", "upiTransactionId": "123456789012",
                "couponId": "waiver-50", "expectedAmountPaise": "25000",
            ],
            sent
        )
    }

    func testAOneTimeFeeIsSentForMonth01AndTheStandardFeeAsNone() async {
        oneTimeFee.value = true
        let vm = await model()
        vm.selectMonth(9)
        let sent = await submitted(vm)
        XCTAssertEqual("01", sent["paymentMonth"])
        XCTAssertEqual("none", sent["couponId"])
        XCTAssertEqual("50000", sent["expectedAmountPaise"])
    }

    func testAFullyWaivedFeeSendsNoPaymentMethodOrTransaction() async {
        let vm = await model()
        vm.selectCoupon("waiver-100")
        let sent = await submitted(vm)
        XCTAssertEqual("0", sent["expectedAmountPaise"])
        XCTAssertNil(sent["paymentMethod"])
        XCTAssertNil(sent["upiTransactionId"])
    }

    func testTheEnrollmentFeeSendsNoMonthOrYear() async {
        let sent = await submitted(await model("enrollment"))
        XCTAssertEqual("enrollment", sent["paymentType"])
        XCTAssertNil(sent["paymentMonth"])
        XCTAssertNil(sent["paymentYear"])
    }

    func testARestoredWaiverThatIsNoLongerOfferedIsDropped() async {
        let saved = PaySavedState(["couponId": "withdrawn"])
        let vm = await model(saved: saved)
        XCTAssertNil(vm.state.couponId)
        XCTAssertNil(saved["couponId"])
        XCTAssertEqual(50000, vm.state.amountPaise)
    }
}
