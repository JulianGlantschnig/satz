import XCTest

/// Draws a rectangle in a new document and edits it in the inspector and the layers list.
final class ToolTests: XCTestCase {
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

    func testDrawARectangleAndSizeIt() throws {
        let window = app.windows.firstMatch
        let canvas = window.groups["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        window.radioButtons["Rectangle"].click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.55)))
        sleep(1)
        shot("1-drawn")
        // The new layer is selected, listed and measured in the inspector.
        let width = window.descendants(matching: .any)["field-W"].textFields.firstMatch
        XCTAssertTrue(width.waitForExistence(timeout: 3))
        width.doubleClick()
        width.typeKey("a", modifierFlags: .command)
        width.typeText("2cm + 5\r")
        sleep(1)
        XCTAssertEqual(width.value as? String, "25")
        shot("2-sized")
        XCTAssertTrue(window.outlines.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'layer-'")).firstMatch.exists)
        // A drag out of the top ruler makes a guide.
        let top = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0)).withOffset(CGVector(dx: 0, dy: -10))
        top.press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)))
        sleep(1)
        shot("3-guide")
        app.menuBars.menuBarItems["Edit"].menus.menuItems["Undo"].click()
        app.menuBars.menuBarItems["Edit"].menus.menuItems["Undo"].click()
        sleep(1)
        shot("4-undone")
    }
}
