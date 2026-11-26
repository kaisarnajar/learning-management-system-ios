import XCTest
@testable import DarseQuran

/// Ported from Android's ui/manage/common/AccountCheckTest.kt: answers are held until the test gives them.
@MainActor
final class AccountCheckTests: XCTestCase {
    /// Answers per e-mail, given by the test; a check waits for its e-mail's answer.
    @MainActor
    private final class Answers {
        var waiting: [String: [CheckedContinuation<ApiResult<AccountAnswer>, Never>]] = [:]
        var given: [String: ApiResult<AccountAnswer>] = [:]

        func ask(_ email: String) async -> ApiResult<AccountAnswer> {
            if let r = given[email] { return r }
            return await withCheckedContinuation { waiting[email, default: []].append($0) }
        }

        func answer(_ email: String, _ result: ApiResult<AccountAnswer>) {
            given[email] = result
            waiting.removeValue(forKey: email)?.forEach { $0.resume(returning: result) }
        }
    }

    private var answers: Answers!
    private var check: AccountCheck!

    override func setUp() async throws {
        answers = Answers()
        let answers = answers!
        check = AccountCheck { await answers.ask($0) }
    }

    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    func testAFoundAccountIsVerifiedForThatEmailOnly() async {
        check.edit("amina@example.test"); check.verify(); await settle()
        answers.answer("amina@example.test", .success(AccountAnswer("Amina"))); await settle()
        XCTAssertTrue(check.verified)
        XCTAssertEqual("Amina", check.name)
        check.edit("bilal@example.test")
        XCTAssertFalse(check.verified, "an answer for the previous e-mail doesn't count")
        XCTAssertEqual("", check.name)
    }

    func testCheckingEndsEvenWhenTheCheckIsReplaced() async {
        check.edit("ami"); check.verify(); await settle()
        XCTAssertTrue(check.checking)
        check.edit("amina@example.test"); check.verify(); await settle() // the first is cancelled
        answers.answer("amina@example.test", .success(AccountAnswer("Amina"))); await settle()
        XCTAssertFalse(check.checking)
        XCTAssertTrue(check.verified)
        // A late answer for the replaced check changes nothing.
        answers.answer("ami", .success(AccountAnswer(nil, error: "Not found."))); await settle()
        XCTAssertTrue(check.verified)
        XCTAssertNil(check.error)
    }

    func testAnUnusableAccountSaysWhy() async {
        check.edit("teacher@example.test"); check.verify(); await settle()
        answers.answer("teacher@example.test", .success(AccountAnswer(nil, error: "This account is already a teacher."))); await settle()
        XCTAssertEqual("This account is already a teacher.", check.error)
        XCTAssertFalse(check.verified)
    }

    func testResetClearsEverything() {
        check.restore(email: "amina@example.test", name: "Amina")
        XCTAssertTrue(check.verified)
        check.reset()
        XCTAssertEqual("", check.email)
        XCTAssertNil(check.error)
        XCTAssertFalse(check.verified)
    }

    func testALookupThatIsNotOkIsAnError() {
        XCTAssertEqual(AccountAnswer("Amina"), AccountAnswer(AccountLookup(ok: true, name: "Amina")))
        XCTAssertEqual(AccountAnswer(nil, error: "Already a teacher."), AccountAnswer(AccountLookup(ok: false, name: "Amina", error: "Already a teacher.")))
    }
}
