import XCTest

/// View ▸ Raster…: a template with a header and punch holes among the layout grids, then
/// as a locked layer under the page.
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
        // Among the layout grids, which show now.
        let edit = window.buttons["edit-raster"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        sleep(1)
        shot("2-layout-grid", window)
        // It takes the template's name, which the inspector renames.
        let name = window.textFields["raster-name"]
        XCTAssertEqual(name.value as? String, "Lined Paper with Punch Holes")
        name.doubleClick()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Physik\r")
        // It opens again with its settings, and goes on the page as a layer.
        edit.click()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertEqual(sheet.textFields["raster-window-name"].value as? String, "Physik")
        sheet.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -2000)
        XCTAssertEqual(sheet.textFields["raster-header-text"].value as? String, "Physik")
        sheet.buttons["raster-layer"].click()
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))
        window.showSidebar("Layers")
        let outline = window.outlines.firstMatch
        XCTAssertTrue(outline.waitForExistence(timeout: 5))
        sleep(1)
        // A group's row joins the identifiers of its parts.
        XCTAssertTrue(outline.debugDescription.contains("identifier: 'layer-Raster"))
    }
}
