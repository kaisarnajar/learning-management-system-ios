import XCTest
@testable import DarseQuran

/// Ported from Android's JsonStrictnessTest. Android's debug build parses the API's JSON strictly (no unquoted strings)
/// while ignoring unknown keys and coercing nulls to defaults (coerceInputValues). iOS's JSONDecoder is always strict
/// about syntax; the defaults come from @Default (Data/Remote/Defaults.swift).
final class JsonStrictnessTests: XCTestCase {
    private let decoder = APIClient(sessions: SessionStore(store: MemoryStore(), initialEnvironment: .staging)).decoder

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try decoder.decode(type, from: Data(json.utf8)) }

    func testAnUnquotedStringIsReportedInDebugBuilds() {
        XCTAssertThrowsError(try decode(ErrorBody.self, #"{"error":Unauthorized}"#)) { XCTAssertTrue($0 is DecodingError, "\($0)") }
    }

    func testUnknownKeysAreStillFine() throws {
        XCTAssertEqual(OkResponse(success: true), try decode(OkResponse.self, #"{"success":true,"addedLater":1}"#))
    }

    func testAMissingOrNullFieldWithADefaultTakesTheDefault() throws {
        let course = try decode(Course.self, #"{"id":"c1","title":"Tajweed","description":null,"status":null,"monthlyFeeInrPaise":null}"#)
        XCTAssertEqual(Course(id: "c1", title: "Tajweed"), course)
        XCTAssertEqual("PUBLISHED", course.status)
        XCTAssertEqual(0, course.priceInrPaise)

        let home = try decode(HomeResponse.self, #"{"courses":null}"#)
        XCTAssertEqual([], home.courses)
        XCTAssertEqual([], home.books)

        let user = try decode(SessionUser.self, #"{"id":"u1","email":"one@example.test"}"#)
        XCTAssertEqual("USER", user.role)
        XCTAssertEqual(3600, try decode(TokenResponse.self, #"{"accessToken":"a","refreshToken":"r"}"#).expiresIn)
    }

    func testARequiredFieldStillHasToBeThere() {
        XCTAssertThrowsError(try decode(Course.self, #"{"id":"c1"}"#))
        XCTAssertThrowsError(try decode(Course.self, #"{"id":"c1","title":null}"#))
    }
}
