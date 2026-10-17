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
        print("FRAME", window.frame)
        shot("1-document")
        let canvas = window.groups["canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        shot("2-selection")
        app.menuBars.menuBarItems["File"].menus.menuItems["Preflight"].click()
        shot("3-preflight")
    }

    func testLight() throws { try shots("light") }
    func testDark() throws { try shots("dark") }
}
