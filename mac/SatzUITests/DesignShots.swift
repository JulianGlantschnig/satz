import XCTest

/// Screenshots of the main window in light and dark for the design pass; they assert little.
final class DesignShots: XCTestCase {
    func shots(_ appearance: String) throws {
        let booklet = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "examples/booklet.satz")
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)", "-appearance", appearance]
        app.launchEnvironment["SATZ_RESET_SETTINGS"] = "1"
        app.launchEnvironment["SATZ_OPEN"] = booklet.path
        app.launch()
        defer { app.terminate() }
        let window = app.windows["booklet.satz"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        func shot(_ name: String) {
            sleep(2)
            let a = XCTAttachment(screenshot: window.screenshot())
            a.name = "\(appearance)-\(name)"
            a.lifetime = .keepAlways
            add(a)
        }
        shot("1-document")
        let canvas = window.groups["canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        shot("2-selection")
        app.menuBars.menuBarItems["File"].menus.menuItems["Preflight"].click()
        shot("3-preflight")
        window.showSidebar("Pages")
        shot("4-pages")
    }

    func testLight() throws { try shots("light") }
    func testDark() throws { try shots("dark") }

    func start(_ appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)", "-appearance", appearance]
        app.launchEnvironment["SATZ_RESET_SETTINGS"] = "1"
        app.launch()
        defer { app.terminate() }
        let start = app.windows["New Document"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        sleep(3)
        let a = XCTAttachment(screenshot: start.screenshot())
        a.name = "\(appearance)-5-start"
        a.lifetime = .keepAlways
        add(a)
    }

    func testStartLight() throws { try start("light") }
    func testStartDark() throws { try start("dark") }

    func overlays(_ appearance: String) throws {
        let booklet = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "examples/booklet.satz")
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)", "-appearance", appearance]
        app.launchEnvironment["SATZ_RESET_SETTINGS"] = "1"
        app.launchEnvironment["SATZ_OPEN"] = booklet.path
        app.launch()
        defer { app.terminate() }
        let window = app.windows["booklet.satz"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        func shot(_ name: String, _ e: XCUIElement? = nil) {
            sleep(2)
            let a = XCTAttachment(screenshot: (e ?? window).screenshot())
            a.name = "\(appearance)-\(name)"
            a.lifetime = .keepAlways
            add(a)
        }
        app.menuBars.menuBarItems["View"].menus.menuItems["Command Palette…"].click()
        window.textFields["palette-search"].typeText("align")
        shot("6-palette")
        window.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        app.menuBars.menuBarItems["Help"].menus.menuItems["Keyboard Shortcuts"].click()
        shot("7-shortcuts")
        window.sheets.firstMatch.buttons["Done"].click()
        app.menuBars.menuBarItems["Page"].menus.menuItems["Page Overview"].click()
        shot("8-overview")
        app.menuBars.menuBarItems["Satz"].menus.menuItems["Settings…"].click()
        let settings = app.windows.element(boundBy: 0)
        shot("9-settings", settings)
    }

    func testOverlaysLight() throws { try overlays("light") }
    func testOverlaysDark() throws { try overlays("dark") }
}
