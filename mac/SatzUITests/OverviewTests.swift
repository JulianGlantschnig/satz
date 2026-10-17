import XCTest

/// The page overview of the example booklet.
final class OverviewTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        let booklet = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "examples/booklet.satz")
        app = .satz(opening: booklet)
        XCTAssertTrue(app.windows["booklet.satz"].waitForExistence(timeout: 30))
    }

    override func tearDown() { app.terminate() }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.windows["booklet.satz"].screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testOpenAPageFromTheOverview() throws {
        let window = app.windows["booklet.satz"]
        app.menuBars.menuBarItems["Page"].menus.menuItems["Page Overview"].click()
        let page = window.descendants(matching: .any)["overview-page-2"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        sleep(3)
        shot("1-overview")
        page.doubleClick()
        sleep(1)
        XCTAssertFalse(window.descendants(matching: .any)["overview"].exists)
        XCTAssertTrue(window.outlines.cells.containing(.any, identifier: "page-2").firstMatch.isSelected
            || window.outlines.cells.containing(.any, identifier: "page-3").firstMatch.isSelected)
        shot("2-opened")
    }
}
