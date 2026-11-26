import Foundation
import XCTest
@testable import DarseQuran



/// Waits (up to [timeout]) until [condition] holds on the main actor.
@MainActor
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    let end = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > end { XCTFail("Timed out waiting", file: file, line: line); return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
