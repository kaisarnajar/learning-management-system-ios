import XCTest

extension XCTestCase {
    /// Lets queued main-actor work run until [condition] holds (Android's tests run their coroutines eagerly; here the
    /// models' tasks run on the main actor after the test yields). Fails the test after [timeout].
    @MainActor
    func waitFor(
        _ what: String = "condition", timeout: Duration = .seconds(5), file: StaticString = #filePath, line: UInt = #line,
        _ condition: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now >= deadline { XCTFail("timed out waiting for \(what)", file: file, line: line); return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Lets everything already queued on the main actor run, for checks that something did *not* happen.
    @MainActor
    func settle(for duration: Duration = .milliseconds(100)) async {
        try? await Task.sleep(for: duration)
    }
}

/// Waits until [condition] holds (Kotlin's withTimeout { while (!condition) delay(20) }).
@MainActor
func waitUntil(_ timeout: TimeInterval = 5, _ message: String = "condition", file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { XCTFail("Timed out waiting for \(message)", file: file, line: line); return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}
