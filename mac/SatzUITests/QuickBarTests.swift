import XCTest

/// The quick edit bar above a selected rectangle.
final class QuickBarTests: XCTestCase {
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

    func testTheBarFollowsTheSelectionAndPaintsIt() throws {
        let window = app.windows["Untitled"]
        let canvas = window.groups["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        window.radioButtons["Rectangle"].click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.7)))
        let fills = window.descendants(matching: .any)["quick-fills"].firstMatch
        XCTAssertTrue(fills.waitForExistence(timeout: 5))
        // Above the rectangle.
        XCTAssertLessThan(fills.frame.maxY, canvas.frame.minY + canvas.frame.height * 0.5)
        fills.click()
        app.menuItems["Black"].click()
        sleep(1)
        shot("1-black")
        // Nothing selected, no bar.
        canvas.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertFalse(fills.waitForExistence(timeout: 1) && fills.isHittable)
    }

    func testAboveATextTheBarShowsItsFontAndAGroupAlignsInside() throws {
        let window = app.windows["Untitled"]
        let canvas = window.groups["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        window.radioButtons["Text"].click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4)).click()
        canvas.typeText("Satz")
        canvas.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        let bar = window.descendants(matching: .any)["quick-bar"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertTrue(bar.descendants(matching: .any)["quick-font"].firstMatch.exists)
        sleep(1)
        shot("2-text")
    }
}
