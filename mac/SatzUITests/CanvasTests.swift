import XCTest

/// Drives the canvas with the example booklet. With SATZ_SHOTS set, the window's
/// screenshots are written to that directory for a look.
final class CanvasTests: XCTestCase {
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

    override func tearDown() {
        app.terminate()
    }

    func shot(_ name: String) {
        let window = app.windows["booklet.satz"]
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SATZ_SHOTS"] {
            try? window.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
        }
    }

    /// Picks the menu bar item `title`.
    func menu(_ title: String) {
        let item = app.menuBars.menuItems[title]
        XCTAssertTrue(item.exists, "no menu item \(title)")
        item.click()
    }

    func testSpreadsAndZoom() throws {
        let window = app.windows["booklet.satz"]
        sleep(2)
        shot("1-cover")
        menu("Next Spread")
        sleep(2)
        shot("2-spread")
        XCTAssertTrue(window.outlines.cells.containing(.any, identifier: "page-2").firstMatch.isSelected)
        let zoom = window.toolbars.menuButtons.firstMatch.title
        menu("Zoom In")
        menu("Zoom In")
        sleep(2)
        shot("3-zoomed")
        XCTAssertNotEqual(window.toolbars.menuButtons.firstMatch.title, zoom)
        menu("Show Layout Grids and Guides")
        menu("Zoom to Fit")
        sleep(2)
        shot("4-grids")
        window.outlines.descendants(matching: .any)["master-Body"].firstMatch.click()
        sleep(2)
        shot("5-master")
    }
}
