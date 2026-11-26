import XCTest
@testable import DarseQuran

/// The release build only knows production; the debug build (which unit tests run) starts on staging and can switch.
/// Ported from Android's EnvironmentTest.
final class EnvironmentTests: XCTestCase {
    func testTheReleaseBuildOnlyHasProduction() {
        XCTAssertEqual([.production], AppEnvironment.availableFor(debugBuild: false))
    }

    func testTheDebugBuildHasBothAndStartsOnStaging() {
        XCTAssertEqual([.production, .staging], AppEnvironment.available)
        XCTAssertEqual(.staging, AppEnvironment.defaultEnvironment)
        XCTAssertTrue(AppEnvironment.available.allSatisfy { $0.baseUrl.hasPrefix("https://") }, "\(AppEnvironment.available.map(\.baseUrl))")
    }

    func testARememberedKeyThatNoLongerExistsFallsBackToTheDefault() {
        XCTAssertNil(AppEnvironment.fromKey("local"))
        XCTAssertNil(AppEnvironment.fromKey(nil))
    }
}
