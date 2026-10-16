import XCTest

/// Writes text with the text tool in a new document.
final class TypingTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .satz()
        app.menuBars.menuBarItems["File"].menus.menuItems["New"].click()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
    }

    override func tearDown() { app.terminate() }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testTypeAndSelectText() throws {
        let window = app.windows.firstMatch
        let canvas = window.groups["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        window.radioButtons["Text"].click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.3)).click()
        canvas.typeText("Satz für den Mac")
        sleep(1)
        shot("1-typed")
        canvas.typeKey(.leftArrow, modifierFlags: [.option, .shift])
        sleep(1)
        shot("2-word-selected")
        canvas.typeText("Macintosh")
        canvas.typeKey(.escape, modifierFlags: [])
        sleep(1)
        shot("3-done")
        XCTAssertTrue(window.outlines.descendants(matching: .any)["layer-Satz für den Macintosh"].exists)
    }
}
