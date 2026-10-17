import XCTest

/// The preflight and the export of the example booklet.
final class PreflightTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .satz()
        let booklet = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "examples/booklet.satz")
        app.open(booklet)
        XCTAssertTrue(app.windows["booklet.satz"].waitForExistence(timeout: 30))
    }

    override func tearDown() { app.terminate() }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.windows["booklet.satz"].screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testThePreflightShowsThePlatesAndExports() throws {
        let window = app.windows["booklet.satz"]
        app.menuBars.menuBarItems["File"].menus.menuItems["Export…"].click()
        let export = window.buttons["export"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(window.checkBoxes["plate-Cyan"].exists)
        sleep(3)
        shot("1-preflight")
        // Only the black plate.
        for name in ["Cyan", "Magenta", "Yellow"] { window.checkBoxes["plate-\(name)"].click() }
        sleep(3)
        shot("2-black")
        export.click()
        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertEqual(sheet.textFields.firstMatch.value as? String, "booklet.pdf")
        sheet.buttons["Cancel"].click()
        app.menuBars.menuBarItems["File"].menus.menuItems["Close Preflight"].click()
        XCTAssertFalse(export.waitForExistence(timeout: 1))
    }
}
