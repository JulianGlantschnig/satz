import XCTest

/// View ▸ Raster…: a template, a header and punch holes on the page, then the raster as a
/// locked layer under the page.
final class RasterUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .satz()
        app.menuBars.menuBarItems["File"].menus.menuItems["New"].click()
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: 30))
    }

    override func tearDown() { app.terminate() }

    func shot(_ name: String, _ element: XCUIElement) {
        let a = XCTAttachment(screenshot: element.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testARasterFromATemplateLandsUnderThePage() throws {
        let window = app.windows["Untitled"]
        app.menuBars.menuBarItems["View"].menus.menuItems["Raster…"].click()
        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.descendants(matching: .any)["raster-templates"].firstMatch.click()
        app.menuItems["Lined Paper with Punch Holes"].click()
        sheet.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -2000)
        let header = sheet.checkBoxes["raster-header"]
        header.click()
        let text = sheet.textFields["raster-header-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText("Physik")
        sleep(1)
        shot("1-raster-window", sheet)
        sheet.buttons["raster-apply"].click()
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))
        window.showSidebar("Layers")
        // A group's row joins the identifiers of its parts.
        let outline = window.outlines.firstMatch
        XCTAssertTrue(outline.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertTrue(outline.debugDescription.contains("identifier: 'layer-Raster"))
        sleep(1)
        shot("2-page", window)
        // It opens again with the raster of the page.
        app.menuBars.menuBarItems["View"].menus.menuItems["Raster…"].click()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertEqual(sheet.textFields["raster-header-text"].value as? String, "Physik")
        sheet.buttons["Cancel"].click()
    }
}
