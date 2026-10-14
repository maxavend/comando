import XCTest

final class SmokeUITests: XCTestCase {
    @MainActor func testLaunches() throws {
        let app = XCUIApplication()
        app.launchEnvironment["NATIVETERM_STORE"] = "UITests"
        app.launchEnvironment["NATIVETERM_SKIP_WELCOME"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }
}
