import XCTest
@testable import DarseQuran

/// Ported from Android's FeaturedSwitchTest, FormScreenTest, FormFilesTest and WithOtherTest (ui/manage/common). The
/// Compose UI checks become checks of the rules the views apply. FeaturedSwitchTest's fatwa answer check
/// (answerProblem) belongs to the content section's Fatwa port.
@MainActor
final class FormsTests: XCTestCase {
    // MARK: FeaturedSwitchTest

    func testSlots() {
        XCTAssertTrue(canFeature(currentlyFeatured: false, used: 3, max: 4))
        XCTAssertFalse(canFeature(currentlyFeatured: false, used: 4, max: 4))
        XCTAssertTrue(canFeature(currentlyFeatured: true, used: 4, max: 4), "an item already featured keeps its slot")
    }

    func testAFullHomepageRefusesANewItemButLetsOneGo() {
        let allowed = canFeature(currentlyFeatured: false, used: 4, max: 4)
        XCTAssertFalse(FeaturedSwitch.accepts(true, allowed: allowed))
        XCTAssertTrue(FeaturedSwitch.accepts(false, allowed: allowed))
        XCTAssertEqual(
            "There are already 4 featured answers. Remove one from the homepage to feature this one.",
            featuredDescription(canFeature: allowed, used: 4, max: 4, section: "Fatwa", pageName: "Fatwa page", noun: "answers")
        )
    }

    func testAFreeSlotCanBeUsed() {
        let allowed = canFeature(currentlyFeatured: false, used: 1, max: 4)
        XCTAssertTrue(FeaturedSwitch.accepts(true, allowed: allowed))
        XCTAssertEqual(
            "Featured in the Fatwa section when this answer is published (up to 4; 1/4 slots used). All published answers still appear on the Fatwa page.",
            featuredDescription(canFeature: allowed, used: 1, max: 4, section: "Fatwa", pageName: "Fatwa page", noun: "answers", condition: "when this answer is published")
        )
    }

    // MARK: FormScreenTest

    func testSaveIsDisabledUntilTheRecordHasLoaded() {
        let state = FormSaveState(saving: false, canSave: false)
        XCTAssertFalse(state.saveEnabled)
        XCTAssertFalse(state.failedToLoad)
    }

    func testSaveWorksOnceLoaded() {
        XCTAssertTrue(FormSaveState(saving: false, canSave: true).saveEnabled)
        XCTAssertFalse(FormSaveState(saving: true, canSave: true).saveEnabled, "not twice while saving")
    }

    func testAFailedLoadShowsRetryInsteadOfTheFormAndSave() {
        XCTAssertTrue(FormSaveState(saving: false, canSave: false, loadError: "No connection.", hasRetry: true).failedToLoad)
        // Without a retry the error shows above the fields instead.
        XCTAssertFalse(FormSaveState(saving: false, canSave: false, loadError: "No connection.", hasRetry: false).failedToLoad)
    }

    // MARK: FormFilesTest (no recreation on iOS: the picks live in the screen's model)

    func testPicksAndRemovalMarksAreKept() {
        let files = FormFiles()
        files.picked.append(PickedFile("cover.jpg", "image/jpeg", Data([1, 2])))
        files.removed.insert("img-1")
        XCTAssertEqual(1, files.picked.count)
        XCTAssertEqual(["img-1"], files.removed)
        let reset = FormReset()
        reset.reset()
        XCTAssertEqual(1, reset.generation)
    }

    // MARK: WithOtherTest

    func testAnEmptyListStillOffersOther() { XCTAssertEqual(["Other"], withOther([])) }
    func testOtherIsAddedAtTheEnd() { XCTAssertEqual(["Fiqh", "Seerah", "Other"], withOther(["Fiqh", "Seerah"])) }
    func testOtherIsNotRepeated() { XCTAssertEqual(["Other", "Fiqh"], withOther(["Other", "Fiqh"])) }
    func testAnyCaseCounts() { XCTAssertEqual(["Fiqh", "other"], withOther(["Fiqh", "other"])) }

    // MARK: field helpers

    func testMoneyAndDates() {
        XCTAssertEqual("1250", paiseToRupeesText(125_000))
        XCTAssertEqual("1250.5", paiseToRupeesText(125_050))
        XCTAssertEqual("0.05", paiseToRupeesText(5))
        XCTAssertEqual("", paiseToRupeesText(nil))
        XCTAssertEqual("12.5", moneyInput("12.5"))
        XCTAssertNil(moneyInput("12.505"))
        XCTAssertNil(moneyInput("1.2.3"))
        XCTAssertEqual("125", digitsOnly("1a2-5"))
        XCTAssertEqual("2026-11-26", dateOnly("2026-11-26T10:00:00.000Z"))
        XCTAssertEqual("", dateOnly("2026-13-40"))
        XCTAssertEqual("", dateOnly(nil))
    }
}
