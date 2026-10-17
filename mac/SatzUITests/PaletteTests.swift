import XCTest

/// The command palette and the keyboard shortcuts, with one of them changed.
final class PaletteTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .satz()
        app.menuBars.menuBarItems["File"].menus.menuItems["New"].click()
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: 30))
    }

    override func tearDown() { app.terminate() }

    func shot(_ name: String, _ element: XCUIElement? = nil) {
        let a = XCTAttachment(screenshot: (element ?? app.windows["Untitled"]).screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testThePaletteRunsACommandByItsName() throws {
        let window = app.windows["Untitled"]
        app.menuBars.menuBarItems["View"].menus.menuItems["Command Palette…"].click()
        let search = window.textFields["palette-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("add page")
        shot("1-palette")
        search.typeText("\r")
        XCTAssertFalse(search.waitForExistence(timeout: 1))
        window.showSidebar("Pages")
        XCTAssertTrue(window.outlines.descendants(matching: .any)["page-2"].waitForExistence(timeout: 5))
    }

    func testAShortcutChangesAndComesBack() throws {
        let window = app.windows["Untitled"]
        app.menuBars.menuBarItems["Help"].menus.menuItems["Keyboard Shortcuts"].click()
        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.textFields["shortcuts-search"].click()
        sheet.textFields["shortcuts-search"].typeText("add page")
        let keys = sheet.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'keys-' AND identifier ENDSWITH 'Add Page'")).firstMatch
        XCTAssertTrue(keys.waitForExistence(timeout: 5))
        keys.click()
        sheet.typeKey("j", modifierFlags: [.command, .control])
        sleep(1)
        shot("2-recorded", sheet)
        XCTAssertEqual(keys.label, "⌃⌘J")
        sheet.buttons["Done"].click()
        // The new shortcut adds a page.
        window.groups["canvas"].click()
        window.typeKey("j", modifierFlags: [.command, .control])
        window.showSidebar("Pages")
        XCTAssertTrue(window.outlines.descendants(matching: .any)["page-2"].waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["Help"].menus.menuItems["Keyboard Shortcuts"].click()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.buttons["Reset Shortcuts"].click()
        sheet.buttons["Done"].click()
    }

    func testTheKeysOfAnotherCommandMoveToTheOneGivenThem() throws {
        let window = app.windows["Untitled"]
        app.menuBars.menuBarItems["Help"].menus.menuItems["Keyboard Shortcuts"].click()
        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let keys = { (name: String) in sheet.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", " ▸ " + name)).firstMatch }
        let search = sheet.textFields["shortcuts-search"]
        func find(_ text: String) {
            search.doubleClick()
            search.typeKey("a", modifierFlags: .command)
            search.typeText(text)
        }
        find("image")
        XCTAssertEqual(keys("Place Image…").label, "⇧⌘K")
        find("add page")
        keys("Add Page").click()
        sheet.typeKey("k", modifierFlags: [.command, .shift])
        sleep(1)
        XCTAssertEqual(keys("Add Page").label, "⇧⌘K")
        find("image")
        XCTAssertEqual(keys("Place Image…").label, "—")
        sheet.buttons["Reset Shortcuts"].click()
        XCTAssertEqual(keys("Place Image…").label, "⇧⌘K")
        sheet.buttons["Done"].click()
    }

    func testThePaletteFindsLayersAndFillsWithASwatch() throws {
        let window = app.windows["Untitled"]
        let canvas = window.groups["canvas"]
        window.radioButtons["Rectangle"].click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        canvas.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        app.menuBars.menuBarItems["View"].menus.menuItems["Command Palette…"].click()
        let search = window.textFields["palette-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("layer rectangle\r")
        XCTAssertTrue(window.descendants(matching: .any)["quick-fills"].firstMatch.waitForExistence(timeout: 5))
    }
}
