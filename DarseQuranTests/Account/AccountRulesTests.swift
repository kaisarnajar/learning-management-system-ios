import XCTest
@testable import DarseQuran

/// Ported from Android's ContactRulesTest, NotificationLinksTest, ProfileRulesTest and VerificationBannerTest.
final class ContactRulesTests: XCTestCase {
    private let message = "I would like to know when the next Tajweed class starts."
    private var ok: ContactDraft { ContactDraft(name: "Amina", email: "amina@example.com", phone: "", message: message) }

    func testACompleteFormCanBeSent() { XCTAssertNil(contactError(ok)) }

    func testTheMessageNeedsTwentyCharactersAndAtMostFiveThousand() {
        var d = ok
        d.message = "Too short"
        XCTAssertEqual("Your message must be at least 20 characters.", contactError(d))
        d.message = String(repeating: "x", count: contactMessageMax + 1)
        XCTAssertEqual("Message must be at most 5000 characters.", contactError(d))
        d.message = String(repeating: "x", count: contactMessageMax)
        XCTAssertNil(contactError(d))
    }

    func testNameEmailAndPhoneAreCheckedAsOnTheWebsite() {
        var d = ok
        d.name = " A "
        XCTAssertEqual("Name must be at least 2 characters.", contactError(d))
        d = ok
        d.email = "amina@"
        XCTAssertEqual("Enter a valid email address.", contactError(d))
        d = ok
        d.phone = "12345"
        XCTAssertEqual("Enter a valid phone number with 7 to 15 digits.", contactError(d))
        d.phone = "+91 96229 66911"
        XCTAssertNil(contactError(d))
    }

    func testTheRequestIsTrimmedAndLeavesOutABlankPhone() {
        var d = ok
        d.name = " Amina "
        d.phone = "  "
        d.message = " \(message) "
        XCTAssertEqual(ContactRequest(name: "Amina", email: "amina@example.com", phone: nil, message: message), contactRequest(d))
    }
}

final class NotificationLinksTests: XCTestCase {
    func testEachDestinationIsLabelledAsOnTheWebsite() {
        XCTAssertEqual("View in Payments", relatedPageLabel("/profile/payments?tab=history"))
        XCTAssertEqual("View announcement", relatedPageLabel("/courses/c1/announcements"))
        XCTAssertEqual("View in My Courses", relatedPageLabel("/profile/courses"))
        XCTAssertEqual("View order", relatedPageLabel("/profile/cart"))
        XCTAssertEqual("View order", relatedPageLabel("/bookstore/orders/o1"))
        XCTAssertEqual("View blog post", relatedPageLabel("/blog/a-post"))
        XCTAssertEqual("View related page", relatedPageLabel("/courses/c1"))
    }

    func testTheNotificationsListItselfAndAnEmptyLinkGetNoLabel() {
        XCTAssertNil(relatedPageLabel(""))
        XCTAssertNil(relatedPageLabel("/profile/notifications"))
    }

    func testAnAbsoluteLinkIsReadByItsPath() {
        XCTAssertEqual("View in Payments", relatedPageLabel("https://academy.example/profile/payments"))
    }
}

final class ProfileRulesTests: XCTestCase {
    func testAPhotoIsTakenOnlyOnceTheGenderIsMale() {
        XCTAssertTrue(photoAllowed("MALE"))
        XCTAssertFalse(photoAllowed("FEMALE"))
        XCTAssertFalse(photoAllowed(nil), "the website asks for the gender first")
        XCTAssertFalse(photoAllowed(""))
    }

    func testThePhotoHintIsTheWebsites() {
        XCTAssertEqual("Profile Photo (Optional)", photoHint("MALE"))
        XCTAssertEqual("Profile Photo (Disabled for Female)", photoHint("FEMALE"))
        XCTAssertEqual("Profile Photo (Select gender first)", photoHint(nil))
    }

    func testTheCompleteStepFollowsOnlyTheSaveThatCompletedTheProfile() {
        XCTAssertTrue(profileJustCompleted(wasComplete: false, isComplete: true))
        XCTAssertFalse(profileJustCompleted(wasComplete: true, isComplete: true))
        XCTAssertFalse(profileJustCompleted(wasComplete: false, isComplete: false))
    }
}

final class VerificationBannerTests: XCTestCase {
    func testTheButtonReadsAsOnTheWebsite() {
        XCTAssertEqual("Resend Verification Email", resendLabel(ResendState()))
        XCTAssertEqual("Sending...", resendLabel(ResendState(sending: true)))
        XCTAssertEqual("Sent", resendLabel(ResendState(sent: true)))
    }

    func testAResendThatWentThroughSaysToCheckTheInbox() {
        XCTAssertEqual(ResendState(sent: true, message: verificationSent), resendOutcome(ApiResult<Void>.success(())))
    }

    func testAFailedResendShowsTheServersMessageAndCanBeTriedAgain() {
        let state = resendOutcome(ApiResult<Void>.failure(ApiError(message: "Too many requests. Please try again later.")))
        XCTAssertEqual(ResendState(message: "Too many requests. Please try again later."), state)
        XCTAssertEqual("Resend Verification Email", resendLabel(state))
    }
}
