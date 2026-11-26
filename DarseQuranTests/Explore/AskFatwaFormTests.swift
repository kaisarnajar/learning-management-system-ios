import XCTest
@testable import DarseQuran

/// Ported from Android's AskFatwaFormTest.
final class AskFatwaFormTests: XCTestCase {
    private let valid = AskFatwaForm(
        categoryChoice: "Fiqh",
        title: "Praying while travelling",
        question: "How many rakat should I pray when I am on a journey?",
        name: "Amina",
        email: "amina@example.com"
    )

    func testACompleteFormHasNoErrors() { XCTAssertTrue(valid.errors().isEmpty) }

    func testTheServersMinimumsWithItsMessages() {
        var short = valid
        short.title = "Too short"
        short.question = "Not thirty characters long."
        let errors = short.errors()
        XCTAssertEqual(errors[.title], "Title must be at least 10 characters.")
        XCTAssertEqual(errors[.question], "Question must be at least 30 characters.")
    }

    func testOthersSendsTheTypedCategory() {
        var others = valid
        others.categoryChoice = "Others"
        others.customCategory = "  Zakat  "
        XCTAssertEqual(others.toRequest(websiteUrl: "https://darsequranacademy.com").category, "Zakat")
        others.customCategory = ""
        XCTAssertEqual(others.errors()[.category], "Select a topic.")
        var none = valid
        none.categoryChoice = ""
        XCTAssertEqual(none.errors()[.category], "Select a topic.")
    }

    func testNameAndEmailAreRequiredUnlessAnonymous() {
        var noOne = valid
        noOne.name = ""
        noOne.email = "not-an-email"
        XCTAssertEqual(noOne.errors()[.name], "Name is required.")
        XCTAssertEqual(noOne.errors()[.email], "Enter a valid email address.")
        noOne.anonymous = true
        XCTAssertTrue(noOne.errors().isEmpty)
    }

    func testAnAnonymousQuestionIsRecordedAsTheWebsiteDoes() {
        var anonymous = valid
        anonymous.anonymous = true
        XCTAssertEqual(
            anonymous.toRequest(websiteUrl: "https://darsequranacademy.com/"),
            AskFatwaRequest(title: valid.title, question: valid.question, category: "Fiqh", askerName: "Anonymous", askerEmail: "anonymous@darsequranacademy.com")
        )
    }
}

/// Ported from Android's AskFatwaTest (a Compose UI test there; here the same rules, checked on the model and the
/// values the screen shows).
@MainActor
final class AskFatwaTests: XCTestCase {
    private var server: StubServer!
    private var app: TestApp!

    override func setUp() async throws {
        server = StubServer()
        server.handler = { _ in .json(#"{"success":true}"#) }
        CurrentEnvironment.testBaseUrl = server.baseUrl
        app = TestApp(server)
    }

    override func tearDown() async throws {
        CurrentEnvironment.testBaseUrl = nil
        server = nil
    }

    func testTheWebsitesCategoriesAreOfferedBeforeTheConfigLoads() {
        XCTAssertEqual(askFatwaOptions([]), websiteFatwaCategories)
        XCTAssertTrue(askFatwaOptions([]).contains("Tajweed"))
        XCTAssertEqual(askFatwaOptions(["Salah", "Others"]), ["Salah", "Others"])
    }

    func testPickingOthersAsksForTheCategory() {
        let vm = AskFatwaModel(repo: app.repo)
        vm.edit { $0.categoryChoice = askFatwaOptions(["Salah", "Others"])[1] }
        XCTAssertEqual(vm.form.categoryChoice, otherFatwaCategory) // the screen then shows "Specify Category"
    }

    func testASignedInUserAsksUnderTheirAccount() {
        let vm = AskFatwaModel(repo: app.repo)
        vm.account(name: "Amina", email: "amina@example.com")
        XCTAssertEqual(vm.form.submittingAs, "Submitting as Amina (amina@example.com). We will email you when answered.")
        vm.edit { $0.anonymous = true }
        XCTAssertNil(vm.form.submittingAs)
        vm.account(name: nil, email: nil)
        vm.edit { $0.anonymous = false }
        XCTAssertNil(vm.form.submittingAs) // signed out: the name and e-mail fields are asked for
    }

    func testAQuestionIsSentOnce() async throws {
        let vm = AskFatwaModel(repo: app.repo)
        vm.edit {
            $0.categoryChoice = "Fiqh"
            $0.title = "Praying while travelling"
            $0.question = "How many rakat should I pray when I am on a journey?"
            $0.anonymous = true
        }
        vm.submit(websiteUrl: "https://darsequranacademy.com")
        vm.submit(websiteUrl: "https://darsequranacademy.com")
        await waitUntil { vm.done }
        vm.submit(websiteUrl: "https://darsequranacademy.com")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(server.requests.filter { $0.method == "POST" && $0.path == "/api/v1/fatwa" }.count, 1)
        XCTAssertEqual(server.requests.first?.json(AskFatwaRequest.self)?.askerEmail, "anonymous@darsequranacademy.com")
    }
}
