import XCTest
@testable import DarseQuran

/// The small rules of the people, students and bookstore admin screens (no Android test of their own).
final class PeopleRulesTests: XCTestCase {
    func testTeacherInitialsAsTheWebsiteDerivesThem() {
        XCTAssertEqual("AR", teacherInitialsOf("Abdul Rahman"))
        XCTAssertEqual("AK", teacherInitialsOf("  abdul  bin   karim "))
        XCTAssertEqual("BI", teacherInitialsOf("Bilal"))
        XCTAssertEqual("??", teacherInitialsOf("   "))
    }

    func testAuditJsonIsPrettyPrintedLikeKotlin() {
        XCTAssertEqual("", auditJsonText(nil))
        XCTAssertEqual("", auditJsonText(.null))
        let value = JSONValue.object(["status": .string("PAID"), "amount": .int(500), "tags": .array([.bool(true)]), "none": .object([:])])
        XCTAssertEqual("{\n    \"amount\": 500,\n    \"none\": {},\n    \"status\": \"PAID\",\n    \"tags\": [\n        true\n    ]\n}", auditJsonText(value))
        XCTAssertEqual(1200, auditJsonText(.string(String(repeating: "x", count: 2000))).count)
    }

    func testPaymentMethodLabels() {
        XCTAssertEqual("—", bookOrderPaymentMethodLabel(nil))
        XCTAssertEqual("UPI", bookOrderPaymentMethodLabel("UPI"))
        XCTAssertEqual("Bank transfer", bookOrderPaymentMethodLabel("bank_transfer"))
        XCTAssertEqual("Cash on delivery", bookOrderPaymentMethodLabel("cash_on_delivery"))
    }

    func testReplyMessageSaysWhetherTheEmailWentOut() {
        XCTAssertTrue(inquiryReplySavedMessage(ActionResponse(redirect: "/admin/contact-inquiries/1")).contains("notified by email"))
        XCTAssertTrue(inquiryReplySavedMessage(ActionResponse(redirect: "/x?email=skipped")).contains("SMTP is not configured"))
        XCTAssertTrue(inquiryReplySavedMessage(ActionResponse(redirect: "/x?email=failed")).contains("could not be sent"))
    }

    func testFileNames() {
        XCTAssertEqual("ID_Card_Abdul_Rahman.pdf", studentIdCardFileName("Abdul Rahman"))
        XCTAssertEqual("ID_Card_Student.pdf", studentIdCardFileName(nil))
    }
}
