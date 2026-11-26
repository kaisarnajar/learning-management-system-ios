import XCTest
@testable import DarseQuran

/// Ported from Android's ApiCallTest. HTTP failures are [HTTPError], network ones [URLError] and unexpected JSON a
/// [DecodingError] (Retrofit's HttpException, IOException and SerializationException).
final class ApiCallTests: XCTestCase {
    private struct Boom: Error, CustomStringConvertible {
        var description: String { "Expected BEGIN_OBJECT at com.darsequran.academy.data.remote.Course" }
    }

    private func httpError(_ status: Int, _ body: String = "") -> HTTPError { HTTPError(status: status, body: Data(body.utf8)) }

    private func failWith(_ error: Error) async -> ApiError {
        let result: ApiResult<Void> = await apiCall { throw error }
        guard let e = result.error else { XCTFail("expected a failure"); return ApiError(message: "") }
        return e
    }

    func testOkWrapsTheValue() async {
        let result = await apiCall { 42 }
        XCTAssertEqual(42, result.value)
    }

    func testServerMessageAndCodeAreUsed() async {
        let err = await failWith(httpError(400, #"{"success":false,"error":"Coupon expired.","code":"COUPON_EXPIRED"}"#))
        XCTAssertEqual("Coupon expired.", err.message)
        XCTAssertEqual(400, err.status)
        XCTAssertEqual("COUPON_EXPIRED", err.code)
    }

    func testStatusFallbacksWithoutAServerMessage() async {
        let m401 = await failWith(httpError(401)).message
        let m403 = await failWith(httpError(403)).message
        let m404 = await failWith(httpError(404)).message
        let m429 = await failWith(httpError(429)).message
        let m503 = await failWith(httpError(503)).message
        let m418 = await failWith(httpError(418)).message
        XCTAssertEqual("Please sign in again.", m401)
        XCTAssertEqual("You don't have access to this.", m403)
        XCTAssertEqual("Not found.", m404)
        XCTAssertEqual("Too many attempts. Please wait a moment and try again.", m429)
        XCTAssertEqual("The academy's server had a problem. Please try again.", m503)
        XCTAssertEqual("Something went wrong (418).", m418)
    }

    func testAnHtmlErrorPageFallsBackToTheStatusMessage() async {
        let message = await failWith(httpError(404, "<html>Not Found</html>")).message
        XCTAssertEqual("Not found.", message)
    }

    func testNetworkFailureSaysNoConnection() async {
        let message = await failWith(URLError(.timedOut)).message
        XCTAssertEqual("No connection. Check your internet and try again.", message)
    }

    func testUnexpectedJsonSaysTheServerDiffers() async {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        let message = await failWith(decoding).message
        XCTAssertTrue(message.hasPrefix("The server's answer wasn't what this app expects."), message)
    }

    func testUnexpectedExceptionsDoNotShowTheirMessage() async {
        let err = await failWith(Boom())
        XCTAssertEqual("Something went wrong. Please try again.", err.message)
    }

    /// Android rethrows CancellationException; iOS's apiCall doesn't throw, so a cancelled call comes back marked
    /// [ApiError.cancelled] with nothing to show, and callers drop it.
    func testCancellationIsRethrown() async {
        let cancelled = await failWith(CancellationError())
        XCTAssertTrue(cancelled.cancelled)
        XCTAssertEqual("", cancelled.message)
        let urlCancelled = await failWith(URLError(.cancelled))
        XCTAssertTrue(urlCancelled.cancelled)
    }
}
