import XCTest
@testable import DarseQuran

/// Ported from Android's data/staff/ActionResponseTest.kt (plus the multipart form builder and `result` reading).
final class ActionResponseTests: XCTestCase {
    private func outcome(_ redirect: String?) -> EmailOutcome { ActionResponse(redirect: redirect).emailOutcome() }

    func testNoEmailParameterMeansItWasSent() {
        XCTAssertEqual(.sent, outcome("/admin/fatwa/q1"))
        XCTAssertEqual(.sent, outcome(nil))
        XCTAssertEqual(.sent, outcome("/admin/inquiries?page=2&emailed=1"))
    }

    func testTheWebsiteSaysWhenItDidNotGoOut() {
        XCTAssertEqual(.anonymous, outcome("/admin/fatwa?email=anonymous"))
        XCTAssertEqual(.notConfigured, outcome("/admin/inquiries?page=1&email=skipped"))
        XCTAssertEqual(.failed, outcome("/admin/inquiries?email=failed#top"))
    }

    func testResultFieldsAreReadAsText() throws {
        let json = #"{"success":true,"redirect":"/admin/certificates/e1","result":{"id":"e1","count":3,"nested":{"a":1}}}"#
        let r = try JSONDecoder().decode(ActionResponse.self, from: Data(json.utf8))
        XCTAssertEqual("e1", r.stringResult("id"))
        XCTAssertEqual("3", r.stringResult("count"))
        XCTAssertNil(r.stringResult("nested"))
        XCTAssertNil(r.stringResult("missing"))
        // A bare answer still decodes: success defaults to true.
        XCTAssertTrue(try JSONDecoder().decode(ActionResponse.self, from: Data("{}".utf8)).success)
    }

    func testFormsSendWhatAnHtmlFormSends() {
        let body = formOf { f in
            f.text("name", "Amina")
            f.text("missing", nil)
            f.text("empty", "")
            f.check("published", true)
            f.check("featured", false)
            f.texts("tags", ["a", "b"])
            f.number("max", 20)
            f.file("image", PickedFile("cover.jpg", "image/jpeg", Data([1, 2])))
        }
        XCTAssertEqual(body.fields.map(\.0), ["name", "empty", "published", "tags", "tags", "max"])
        XCTAssertEqual(body.fields.map(\.1), ["Amina", "", "on", "a", "b", "20"])
        XCTAssertEqual(body.files.map(\.filename), ["cover.jpg"])
        // An empty form still sends one harmless field.
        XCTAssertEqual(formOf { _ in }.fields.map(\.0), ["_"])
    }
}
