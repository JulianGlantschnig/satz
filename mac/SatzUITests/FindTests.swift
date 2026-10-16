import XCTest

/// Finds and replaces across the stories of the example booklet.
final class FindTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .satz()
        let booklet = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "examples/booklet.satz")
        app.open(booklet)
        XCTAssertTrue(app.windows["booklet.satz"].waitForExistence(timeout: 30))
    }

    override func tearDown() { app.terminate() }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.windows["booklet.satz"].screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// A text in the window whose label or value contains `s`.
    func text(containing s: String) -> XCUIElement {
        app.windows["booklet.satz"].staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", s, s)).firstMatch
    }

    func testFindAndReplaceAll() throws {
        let window = app.windows["booklet.satz"]
        app.menuBars.menuBarItems["Edit"].menus.menuItems["Find and Replace…"].click()
        let query = window.textFields["find-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.click()
        query.typeText("Moon\r")
        sleep(2)
        shot("1-found")
        XCTAssertTrue(text(containing: " of 6").exists)
        let replacement = window.textFields["find-replacement"]
        replacement.click()
        replacement.typeText("Mond")
        window.buttons["Replace All"].click()
        sleep(2)
        shot("2-replaced")
        XCTAssertTrue(text(containing: "Replaced 6").exists)
        XCTAssertTrue(text(containing: "0 found").exists)
    }
}
