import XCTest
@testable import DarseQuran

/// The money path an admin takes most: confirming or declining a student's fee payment. Ported from Android's
/// ui/manage/money/PaymentApprovalTest.kt: Android taps the card's and the dialog's buttons; here the test drives the
/// screen's model the same way (the card's Confirm / Decline open the dialog, the dialog's button sends).
@MainActor
final class PaymentApprovalTests: XCTestCase {
    private var server: StubServer!

    override func setUp() async throws {
        server = StubServer()
        server.handler = { request in
            switch request.path {
            case "/api/v1/admin/payments":
                .json(#"""
                {"data":[{"kind":"submission","id":"p1","amountInrPaise":50000,"status":"pending",
                  "user":{"name":"Amina","email":"amina@example.test"},"courseTitle":"Tajweed"}],
                  "totalCount":1}
                """#)
            case "/api/v1/admin/payments/p1/approve", "/api/v1/admin/payments/p1/decline":
                .json(#"{"success":true}"#)
            default:
                .json("{}", status: 404)
            }
        }
    }

    override func tearDown() async throws { CurrentEnvironment.testBaseUrl = nil; server = nil }

    private func count(_ what: String) -> Int { server.requests.filter { "\($0.method) \($0.path)" == what }.count }

    private func openScreen() async -> MoneyPendingModel {
        let model = MoneyPendingModel(app: testContainer(server))
        await waitUntil { model.list.state.items.contains { $0.user?.name == "Amina" } }
        return model
    }

    func testConfirmingApprovesOnceAndReloadsTheList() async {
        let model = await openScreen()
        let listLoads = count("GET /api/v1/admin/payments")
        let row = model.list.state.items[0]
        model.decide(row, approve: true) // the card's Confirm
        XCTAssertEqual("p1", model.approving?.id)
        XCTAssertTrue(MoneyPendingModel.approveMessage(row).hasSuffix("from Amina and notify the student?"))
        XCTAssertEqual("Approve this payment of ₹500 from Amina and notify the student?", MoneyPendingModel.approveMessage(row))
        await settle()
        XCTAssertEqual(0, count("POST /api/v1/admin/payments/p1/approve"), "not sent before the dialog is confirmed")
        model.approve(row) // the dialog's Confirm
        await waitUntil { self.count("GET /api/v1/admin/payments") > listLoads }
        XCTAssertEqual(1, count("POST /api/v1/admin/payments/p1/approve"))
        XCTAssertEqual(0, count("POST /api/v1/admin/payments/p1/decline"))
    }

    func testDecliningAsksFirstThenDeclinesOnce() async {
        let model = await openScreen()
        let row = model.list.state.items[0]
        model.decide(row, approve: false) // the card's Decline
        XCTAssertEqual("p1", model.declining?.id)
        XCTAssertNil(model.approving)
        await settle()
        XCTAssertEqual(0, count("POST /api/v1/admin/payments/p1/decline"), "not sent before the dialog is confirmed")
        model.decline(row) // the dialog's Decline
        await waitUntil { self.count("POST /api/v1/admin/payments/p1/decline") == 1 }
        XCTAssertEqual(0, count("POST /api/v1/admin/payments/p1/approve"))
    }

    func testTheTabCountsComeWithThePage() async {
        server.handler = { _ in .json(#"{"data":[],"totalCount":0,"counts":{"enrollment_pending":2,"monthly_pending":0}}"#) }
        let model = MoneyPendingModel(app: testContainer(server))
        await waitUntil { model.counts.value != nil }
        XCTAssertEqual(2, model.counts.value?["enrollment_pending"])
        XCTAssertTrue(server.requests.first?.url.query?.contains("type=enrollment_pending") ?? false, "the first tab is enrolment fees")
    }
}
