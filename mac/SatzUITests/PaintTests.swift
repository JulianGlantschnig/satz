import XCTest

/// Colours a rectangle through the fill's colour picker.
final class PaintUITests: XCTestCase {
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

    func testColourARectangle() throws {
        let window = app.windows.firstMatch
        let canvas = window.groups["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        window.radioButtons["Rectangle"].click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)))
        let well = window.buttons["Fill"].firstMatch
        XCTAssertTrue(well.waitForExistence(timeout: 5))
        well.click()
        let hex = app.popovers.textFields["Hex"].firstMatch
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        hex.doubleClick()
        hex.typeKey("a", modifierFlags: .command)
        hex.typeText("E8590C\r")
        sleep(1)
        shot("1-coloured")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.menuBars.menuBarItems["Edit"].menus.menuItems["Undo"].isEnabled)
    }
}
