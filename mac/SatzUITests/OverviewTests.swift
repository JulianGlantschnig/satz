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

    func testABandPicksThePagesItTouches() throws {
        let window = app.windows["booklet.satz"]
        app.menuBars.menuBarItems["Page"].menus.menuItems["Page Overview"].click()
        let p2 = window.descendants(matching: .any)["overview-page-2"]
        let p3 = window.descendants(matching: .any)["overview-page-3"]
        XCTAssertTrue(p3.waitForExistence(timeout: 5))
        // From beside page 2, above the spread, to the middle of page 3.
        let start = p2.coordinate(withNormalizedOffset: CGVector(dx: -0.15, dy: -0.04))
        start.press(forDuration: 0.1, thenDragTo: p3.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        sleep(1)
        shot("3-band")
        XCTAssertTrue(p2.isSelected)
        XCTAssertTrue(p3.isSelected)
        XCTAssertFalse(window.descendants(matching: .any)["overview-page-4"].isSelected)
    }
}
