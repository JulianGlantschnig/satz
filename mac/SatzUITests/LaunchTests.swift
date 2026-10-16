import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testANewDocumentOpensWithItsPage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)"]
        app.launch()
        app.typeKey("n", modifierFlags: .command)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.outlines.descendants(matching: .any)["page-1"].waitForExistence(timeout: 5))
    }
}
