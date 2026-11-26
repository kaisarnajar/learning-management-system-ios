import XCTest
@testable import DarseQuran

/// Ported from Android's AppRootSessionTest, for the logic iOS keeps outside the views: which tabs each role gets
/// (Shell) and that a new navigation starts on Home with empty stacks. AppRoot gives every server/role/user its own
/// Navigator through a SwiftUI `.id`, which a unit test can't drive.
final class AppRootSessionTests: XCTestCase {
    func testStaffKeepThePublicTabsAndGetTheirOwnEntry() {
        let teacher = Shell.of("TEACHER")
        XCTAssertEqual(.teacher, teacher)
        XCTAssertEqual([.home, .courses, .explore, .staff, .account], teacher.tabs)
        XCTAssertEqual("Teach", teacher.staffLabel)

        let admin = Shell.of("ADMIN")
        XCTAssertEqual([.home, .courses, .explore, .staff, .account], admin.tabs)
        XCTAssertEqual("Admin", admin.staffLabel)
        XCTAssertTrue(admin.adminPanel)

        let developer = Shell.of("DEVELOPER")
        XCTAssertEqual("Developer", developer.staffLabel)
        XCTAssertTrue(developer.adminPanel)

        XCTAssertEqual([.home, .courses, .explore, .account], Shell.of("USER").tabs)
        XCTAssertEqual(.student, Shell.of(nil))
    }

    @MainActor
    func testAnotherStudentDoesNotLandOnThePreviousStudentsScreen() {
        let amina = Navigator(shell: .student)
        amina.switchTab(.account)
        amina.push(.signIn)
        let bilal = Navigator(shell: .student) // what AppRoot builds for the next user
        XCTAssertEqual(.home, bilal.tab)
        XCTAssertTrue(bilal.paths.isEmpty)
    }
}
