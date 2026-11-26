import SwiftUI
import UIKit
import XCTest
@testable import DarseQuran

/// The pay screen follows the website's EnrollmentPaymentForm / MonthlyPaymentForm / PaymentDetailsPanel (Android's
/// PayWordingTest).
final class PayWordingTests: XCTestCase {
    func testSubmitButtonsUseTheWebsitesWording() {
        XCTAssertEqual("Submit enrollment fee for verification", paySubmitLabel("enrollment", free: false))
        XCTAssertEqual("Claim Fee Waiver & Enroll", paySubmitLabel("enrollment", free: true))
        XCTAssertEqual("Submit fee payment for verification", paySubmitLabel("course", free: false))
        XCTAssertEqual("Claim Fee Waiver", paySubmitLabel("course", free: true))
    }

    func testAnyFilledInReferenceIsEnough() {
        XCTAssertTrue(canSubmitPayment(free: false, reference: "A1"))
        XCTAssertFalse(canSubmitPayment(free: false, reference: ""))
        XCTAssertFalse(canSubmitPayment(free: false, reference: "  "))
        XCTAssertTrue(canSubmitPayment(free: true, reference: ""))
    }

    func testTheUpiNoteMatchesTheWebsitesForms() {
        XCTAssertEqual("Tajweed enrollment", feePaymentNote("enrollment", "Tajweed", nil))
        XCTAssertEqual("Tajweed — Quarterly", feePaymentNote("course", "Tajweed", "Quarterly"))
        XCTAssertEqual("Tajweed — Monthly", feePaymentNote("course", "Tajweed", nil))
        XCTAssertEqual(80, feePaymentNote("enrollment", String(repeating: "x", count: 100), nil).count)
    }

    func testTheQrCodeHoldsTheWebsitesUpiLink() {
        let settings = PaymentSettings(upiId: "academy@upi", upiPayeeName: "Darse Quran")
        XCTAssertEqual(
            "upi://pay?pa=academy%40upi&pn=Darse+Quran&am=500.00&cu=INR&tn=Tajweed+enrollment&tr=FEE-50000",
            upiQrUri(settings, amountPaise: 50_000, note: "Tajweed enrollment")
        )
        XCTAssertEqual("upi://pay?pa=academy%40upi&pn=Darse+Quran&cu=INR", upiQrUri(settings, amountPaise: nil, note: nil))
        XCTAssertEqual("upi://pay?pa=academy%40upi&pn=Darse+Quran&cu=INR", upiQrUri(settings, amountPaise: 0, note: "x"))
        XCTAssertTrue(upiQrUri(settings, amountPaise: 100, note: "n", paymentRef: "ORDER-7").hasSuffix("&tr=ORDER-7"))
        XCTAssertEqual("upi://pay?pa=a%40b&pn=Darse+Quran+Academy&cu=INR", upiVpaUri(PaymentSettings(upiId: "a@b", upiPayeeName: " ")))
    }

    func testTheQrCodeHasTheWebsitesQuietZone() throws {
        let matrix = try XCTUnwrap(qrMatrix("upi://pay?pa=academy%40upi&pn=Darse+Quran&cu=INR"))
        XCTAssertEqual(matrix.count, matrix[0].count)
        // Two light modules on every side, then the finder pattern's dark corner.
        XCTAssertFalse(matrix[1][1])
        XCTAssertTrue(matrix[2][2])
    }
}

/// launchUpi (Android's LaunchUpiTest). The Simulator has no UPI app, so only the fallback can run here; the link a UPI
/// app would get is checked instead of the chooser.
@MainActor
final class LaunchUpiTests: XCTestCase {
    private let settings = PaymentSettings(upiId: "academy@upi")

    func testWithoutAUpiAppItSaysSoInsteadOfOpeningAnything() async {
        let opened: Bool = await withCheckedContinuation { done in
            launchUpi(settings, amountPaise: 50000, note: "Course fee") { done.resume(returning: $0) }
        }
        XCTAssertFalse(opened)
    }

    func testTheUpiAppGetsThePayeeAmountAndNote() throws {
        let url = try XCTUnwrap(upiLaunchUri(settings, amountPaise: 50000, note: "Course fee"))
        XCTAssertEqual("upi", url.scheme)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(["pa": "academy@upi", "pn": "Darse Quran Academy", "am": "500.00", "cu": "INR", "tn": "Course fee"], values)
        XCTAssertNil(upiLaunchUri(PaymentSettings(upiId: " "), amountPaise: 100, note: "x"))
    }
}

/// Android's PaymentConfirmFieldsTest: the reference keeps only letters and digits. Rendered in a window and typed into
/// the real text field. (SwiftUI's texts aren't readable from a unit test, so the "Bank transfer" choice and the
/// supporting line are checked on the Pay screen in the Simulator instead.)
@MainActor
final class PaymentConfirmFieldsTests: XCTestCase {
    func testReferenceKeepsOnlyLettersAndDigits() async throws {
        let typed = Box("")
        let proof = ProofImagePicker()
        struct Harness: View {
            let proof: ProofImagePicker
            let typed: Box<String>
            @State var method = "upi"
            @State var reference = ""
            var body: some View {
                VStack {
                    PaymentConfirmFields(
                        settings: PaymentSettings(upiId: "academy@upi", bankAccountNumber: "1234567890"),
                        method: $method,
                        reference: Binding(get: { reference }, set: { reference = $0; typed.value = $0 }),
                        proof: proof
                    )
                }
                .environment(Toaster())
            }
        }
        let host = UIHostingController(rootView: Harness(proof: proof, typed: typed))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(200))

        let field = try XCTUnwrap(textFields(host.view).first)
        field.becomeFirstResponder()
        field.insertText("4127-8890 1234")
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual("412788901234", typed.value)
    }

    private func textFields(_ view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(textFields)
    }
}
