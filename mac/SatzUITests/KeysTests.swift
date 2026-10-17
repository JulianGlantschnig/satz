import XCTest

/// The keys of the canvas that the web app has: align with Option, F2, Esc in the preflight.
final class KeysTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .satz()
        app.menuBars.menuBarItems["File"].menus.menuItems["New"].click()
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: 30))
    }

    override func tearDown() { app.terminate() }

    func testOptionKeysAlignAndF2Renames() throws {
        let window = app.windows["Untitled"]
        let canvas = window.groups["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        for (x, y) in [(0.35, 0.3), (0.5, 0.6)] {
            window.radioButtons["Rectangle"].click()
            canvas.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
                .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: x + 0.1, dy: y + 0.1)))
        }
        app.menuBars.menuBarItems["Edit"].menus.menuItems["Select All"].click()
        let x = window.descendants(matching: .any)["field-X"].textFields.firstMatch
        XCTAssertEqual(x.value as? String, "")
        canvas.typeKey("a", modifierFlags: .option)
        XCTAssertNotEqual(x.value as? String, "")
        // F2 names the first selected layer in the layers list.
        canvas.typeKey(XCUIKeyboardKey.F2, modifierFlags: [])
        let name = window.outlines.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Left\r")
        XCTAssertTrue(window.outlines.descendants(matching: .any)["Left"].waitForExistence(timeout: 5))
        // Esc leaves the preflight once nothing is selected.
        app.menuBars.menuBarItems["File"].menus.menuItems["Preflight"].click()
        XCTAssertTrue(window.buttons["export"].waitForExistence(timeout: 5))
        canvas.click()
        canvas.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        canvas.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertFalse(window.buttons["export"].waitForExistence(timeout: 2))
    }
}
