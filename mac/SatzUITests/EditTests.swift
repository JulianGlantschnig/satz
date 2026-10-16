import XCTest

/// Clicks, drags and menus on the canvas of the example poster.
final class EditTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)"]
        app.launch()
        let poster = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "examples/poster.satz")
        app.open(poster)
        XCTAssertTrue(app.windows["poster.satz"].waitForExistence(timeout: 10))
    }

    override func tearDown() { app.terminate() }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.windows["poster.satz"].screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// The item `title` of the menu `menu`.
    func item(_ menu: String, _ title: String) -> XCUIElement {
        app.menuBars.menuBarItems[menu].menus.menuItems[title]
    }

    func menu(_ title: String, in menu: String = "Object") {
        let item = item(menu, title)
        XCTAssertTrue(item.exists, "no menu item \(title)")
        item.click()
    }

    func testSelectMoveAndUndo() throws {
        let canvas = app.windows["poster.satz"].groups["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        sleep(2)
        // The title "Earthrise" sits a little below the middle of the poster.
        let title = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
        title.click()
        sleep(1)
        shot("1-selected")
        XCTAssertTrue(item("Object", "Duplicate").isEnabled)
        title.press(forDuration: 0.2, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        sleep(1)
        shot("2-moved")
        XCTAssertTrue(item("Edit", "Undo").isEnabled)
        menu("Duplicate")
        sleep(1)
        shot("3-duplicated")
        menu("Undo", in: "Edit")
        menu("Undo", in: "Edit")
        sleep(1)
        shot("4-undone")
        // A drag from beside the page selects with a marquee.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.05))
            .press(forDuration: 0.2, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.95)))
        sleep(1)
        shot("5-marquee")
        XCTAssertTrue(item("Object", "Group").isEnabled)
    }
}
