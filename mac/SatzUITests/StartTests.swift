import XCTest

/// The start window: a format, its orientation and pages, or an example.
final class StartTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .satz()
    }

    override func tearDown() { app.terminate() }

    func shot(_ window: XCUIElement, _ name: String) {
        let a = XCTAttachment(screenshot: window.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testAFormatMakesADocumentOfItsPages() throws {
        let start = app.windows["New Document"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        XCTAssertFalse(app.windows["Open"].exists)
        start.buttons["format-A4"].click()
        start.radioButtons["Landscape"].click()
        let pages = start.descendants(matching: .any)["field-Pages"].textFields.firstMatch
        pages.doubleClick()
        pages.typeText("3\r")
        shot(start, "start")
        start.buttons["create"].click()
        let window = app.windows["Untitled"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        XCTAssertTrue(window.outlines.descendants(matching: .any)["page-3"].waitForExistence(timeout: 5))
        XCTAssertFalse(start.exists)
        // The pages are A4 landscape.
        let w = window.descendants(matching: .any)["field-W"].textFields.firstMatch
        XCTAssertTrue(w.waitForExistence(timeout: 5))
        XCTAssertEqual(w.value as? String, "297")
        app.menuBars.menuBarItems["File"].menus.menuItems["New from Format…"].click()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    func testAnExampleOpensAsANewDocument() throws {
        let start = app.windows["New Document"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        start.buttons["example-booklet"].click()
        let window = app.windows["Untitled"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        XCTAssertTrue(window.outlines.descendants(matching: .any)["page-8"].waitForExistence(timeout: 5))
        XCTAssertFalse(start.exists)
    }

    func testTheUnitOfTheSettingsShowsInTheFormats() throws {
        let start = app.windows["New Document"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        let a4 = start.buttons["format-A4"]
        XCTAssertEqual(a4.label, "A4, 210 × 297")
        app.menuBars.menuBarItems["Satz"].menus.menuItems["Settings…"].click()
        let unit = app.popUpButtons["unit"]
        XCTAssertTrue(unit.waitForExistence(timeout: 5))
        unit.click()
        app.menuItems["Inches (in)"].click()
        sleep(1)
        XCTAssertEqual(a4.label.replacing(",", with: ".").replacing("A4. ", with: "A4, "), "A4, 8.3 × 11.7")
        unit.click()
        app.menuItems["Millimetres (mm)"].click()
    }
}
