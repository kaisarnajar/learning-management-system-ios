import XCTest
@testable import DarseQuran

/// Ported from Android's SavedHomeTest.
final class SavedHomeTests: XCTestCase {
    private var folder: URL!
    private var file: URL { folder.appendingPathComponent("home.json") }

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SavedHomeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    func testWhatIsWrittenIsReadBackByTheNextRun() {
        let home = HomeResponse(courses: [Course(id: "c1", title: "Tajweed")])
        SavedHome(file: file).write(home)
        XCTAssertEqual(home, SavedHome(file: file).read())
    }

    func testNothingSavedReadsAsNothing() {
        XCTAssertNil(SavedHome(file: file).read())
    }

    func testAFileThatNoLongerReadsIsIgnored() throws {
        try Data("{not json".utf8).write(to: file)
        XCTAssertNil(SavedHome(file: file).read())
    }
}
