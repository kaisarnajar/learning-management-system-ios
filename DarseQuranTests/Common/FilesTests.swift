import XCTest
@testable import DarseQuran

/// Ported from Android's FilesTest.
final class FilesTests: XCTestCase {
    private var server: StubServer!

    override func setUp() {
        server = StubServer()
        CurrentEnvironment.testBaseUrl = server.baseUrl
    }

    override func tearDown() {
        CurrentEnvironment.testBaseUrl = nil
        server = nil
    }

    private func client() -> APIClient {
        APIClient(sessions: SessionStore(store: MemoryStore(), initialEnvironment: CurrentEnvironment.value), urlSession: server.session)
    }

    func testAGenericTypeFallsBackToTheExtension() {
        XCTAssertEqual("application/pdf", mimeFor(fileName: "notes.pdf", contentType: "application/octet-stream"))
        XCTAssertEqual("application/pdf", mimeFor(fileName: "notes.PDF", contentType: nil))
        XCTAssertEqual("image/png", mimeFor(fileName: "diagram.png", contentType: "binary/octet-stream"))
        XCTAssertEqual("application/pdf", mimeFor(fileName: "whatever", contentType: "application/pdf; charset=binary"))
        XCTAssertEqual("application/octet-stream", mimeFor(fileName: "archive", contentType: nil))
    }

    /// Android also checks the body is streamed rather than held in memory; iOS's download reads it whole (see the
    /// report), so this checks the part both share: all of a large file lands in the document cache.
    func testALargeFileIsStreamedIntoTheCache() async throws {
        let size = 5 * 1024 * 1024
        let body = Data((0..<size).map { UInt8($0 % 251) })
        server.handler = { _ in StubServer.Response(status: 200, body: body, headers: ["Content-Type": "application/pdf"]) }
        let file = try await client().download("/api/files/a1/lesson.pdf", fileName: "lesson.pdf")
        XCTAssertEqual(DocumentCache.file(named: "lesson.pdf"), file)
        let written = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
        XCTAssertEqual(size, written)
        XCTAssertEqual(body, try Data(contentsOf: file))
    }

    /// Cancelled, not a message: downloadAndOpen returns no error text when the screen goes away mid-download.
    @MainActor
    func testLeavingTheScreenCancelsTheDownloadInsteadOfReportingAnError() async {
        server.handler = { _ in
            Thread.sleep(forTimeInterval: 3) // a server slow to answer
            return StubServer.Response(status: 200, body: Data("late".utf8), headers: ["Content-Type": "application/pdf"])
        }
        let client = client()
        let download = Task { await downloadAndOpen(client, path: "/api/files/a1/lesson.pdf", fileName: "lesson.pdf") }
        try? await Task.sleep(for: .milliseconds(200))
        download.cancel()
        let started = ContinuousClock.now
        let outcome = await download.value
        XCTAssertNil(outcome, "cancelled, not a message: \(outcome ?? "")")
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(2), "the download stops instead of waiting for the server")
    }
}
