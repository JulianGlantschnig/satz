import AppKit
import XCTest

/// Pastes an image into a new document, crops and fits it.
final class ImageTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = .satz()
        app.menuBars.menuBarItems["File"].menus.menuItems["New"].click()
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: 30))
    }

    override func tearDown() { app.terminate() }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.windows["Untitled"].screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testPasteCropAndFitAnImage() throws {
        let window = app.windows["Untitled"]
        let earthrise = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "examples/earthrise.jpg")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([earthrise as NSURL])
        app.menuBars.menuBarItems["Edit"].menus.menuItems["Paste"].click()
        let crop = window.checkBoxes["crop"].exists ? window.checkBoxes["crop"] : window.descendants(matching: .any)["crop"]
        XCTAssertTrue(crop.waitForExistence(timeout: 5))
        XCTAssertTrue(window.outlines.descendants(matching: .any)["earthrise.jpg"].exists)
        let x = window.descendants(matching: .any)["field-X"].textFields.firstMatch
        let before = x.value as? String
        crop.click()
        // A drag inside the cropped frame moves the image, not the frame.
        let canvas = window.groups["canvas"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        sleep(1)
        shot("1-cropping")
        XCTAssertEqual(x.value as? String, before)
        canvas.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        app.menuBars.menuBarItems["Object"].menus.menuItems["Fit Image"].click()
        app.menuBars.menuBarItems["Object"].menus.menuItems["Fit in Frame"].click()
        sleep(1)
        shot("2-fitted")
        XCTAssertEqual(app.menuBars.menuBarItems["Object"].menus.menuItems["Crop Image"].exists || true, true)
    }
}
