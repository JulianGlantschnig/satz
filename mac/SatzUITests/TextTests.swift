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

        // The selected text layer's size and font change in the inspector.
        let size = window.descendants(matching: .any)["field-Size"].textFields.firstMatch
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        size.doubleClick()
        size.typeKey("a", modifierFlags: .command)
        size.typeText("36\r")
        sleep(1)
        XCTAssertEqual(size.value as? String, "36")
        window.descendants(matching: .any)["font-menu"].firstMatch.click()
        let search = app.popovers.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("Helvetica")
        let family = app.popovers.disclosureTriangles.firstMatch
        if family.waitForExistence(timeout: 5) { family.click() }
        let bold = app.popovers.buttons["Bold"].firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 5))
        bold.click()
        sleep(1)
        shot("4-styled")
        XCTAssertTrue(window.descendants(matching: .any)["font-menu"].firstMatch.label.contains("Helvetica")
            || window.buttons.matching(NSPredicate(format: "label CONTAINS 'Helvetica'")).count > 0)
    }
}
