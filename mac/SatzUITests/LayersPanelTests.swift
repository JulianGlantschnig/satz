import XCTest

/// The layers panel lists the page shown, or the spread with a heading per page.
final class LayersPanelTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .satz()
        app.menuBars.menuBarItems["File"].menus.menuItems["New"].click()
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: 30))
    }

    override func tearDown() { app.terminate() }

    func testThePanelNamesThePageOrTheSpread() throws {
        let window = app.windows["Untitled"]
        let heading = window.staticTexts["layers-heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "Layers · Page 1")
        // Facing pages put pages 2 and 3 on one spread.
        for _ in 0..<2 { app.menuBars.menuBarItems["Page"].menus.menuItems["Add Page"].click() }
        let spreads = window.popUpButtons.matching(NSPredicate(format: "value == 'Single Pages'")).firstMatch
        if spreads.waitForExistence(timeout: 3) {
            spreads.click()
            app.menuItems["Facing Pages"].click()
        }
        XCTAssertEqual(heading.label, "Layers · Page 3")
        app.menuBars.menuBarItems["Satz"].menus.menuItems["Settings…"].click()
        let shown = app.popUpButtons["layers-shown"]
        XCTAssertTrue(shown.waitForExistence(timeout: 5))
        shown.click()
        app.menuItems["Current spread"].click()
        app.windows["Satz Settings"].exists ? app.windows["Satz Settings"].buttons[XCUIIdentifierCloseWindow].click() : app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "Layers · Pages 2–3")
    }
}
