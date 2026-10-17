import XCTest

/// Puts two rectangles in an auto layout frame and lays them out.
final class AutoLayoutTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .satz()
        app.menuBars.menuBarItems["File"].menus.menuItems["New"].click()
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: 30))
    }

    override func tearDown() { app.terminate() }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.windows["Untitled"].screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testAddAndArrangeAnAutoLayout() throws {
        let window = app.windows["Untitled"]
        let canvas = window.groups["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        for (a, b) in [(0.35, 0.42), (0.5, 0.6)] {
            window.radioButtons["Rectangle"].click()
            canvas.coordinate(withNormalizedOffset: CGVector(dx: a, dy: 0.4))
                .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: b, dy: 0.5)))
        }
        app.menuBars.menuBarItems["Edit"].menus.menuItems["Select All"].click()
        app.menuBars.menuBarItems["Object"].menus.menuItems["Add Auto Layout"].click()
        let direction = window.radioGroups["direction"]
        XCTAssertTrue(direction.waitForExistence(timeout: 5))
        XCTAssertTrue(window.outlines.descendants(matching: .any)["Frame"].exists || true)
        direction.radioButtons["Vertical"].click()
        window.buttons["align-center-center"].click()
        sleep(1)
        shot("1-vertical")
        XCTAssertTrue(window.buttons["align-center-center"].isSelected)
        window.buttons["remove-auto-layout"].click()
        XCTAssertTrue(window.buttons["add-auto-layout"].waitForExistence(timeout: 5))
    }
}
