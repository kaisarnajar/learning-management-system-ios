import XCTest
@testable import DarseQuran

final class SmokeTests: XCTestCase {
    func testFontsAreBundled() {
        for name in [FontName.serifSemiBold, FontName.sansRegular, FontName.sansSemiBold, FontName.arabicRegular] {
            XCTAssertNotNil(UIFont(name: name, size: 12), name)
        }
    }
}
