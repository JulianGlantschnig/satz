import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testANewDocumentOpensWithItsPage() throws {
        let app = XCUIApplication.satz()
        app.typeKey("n", modifierFlags: .command)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        window.showSidebar("Pages")
        XCTAssertTrue(window.outlines.descendants(matching: .any)["page-1"].waitForExistence(timeout: 5))
    }
}
