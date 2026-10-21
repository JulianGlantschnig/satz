import XCTest

/// The home window: the documents of the Satz folder, favourites, collections and the trash.
final class HomeUITests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        home = FileManager.default.temporaryDirectory.appending(path: "satz-home-\(UUID().uuidString)")
        let folder = home.appending(path: "Satz")
        try FileManager.default.createDirectory(at: folder.appending(path: "Kunden"), withIntermediateDirectories: true)
        let examples = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "examples")
        try FileManager.default.copyItem(at: examples.appending(path: "booklet.satz"), to: folder.appending(path: "Heft.satz"))
        try FileManager.default.copyItem(at: examples.appending(path: "poster.satz"), to: folder.appending(path: "Kunden/Plakat.satz"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func shot(_ name: String, _ element: XCUIElement) {
        let a = XCTAttachment(screenshot: element.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Shows a place of the sidebar, again if a closing menu ate the first click.
    func go(_ window: XCUIElement, _ id: String, _ title: String) {
        for _ in 0..<3 {
            window.descendants(matching: .any)[id].firstMatch.click()
            if NSPredicate(format: "title ENDSWITH %@", title).evaluate(with: window) { return }
            sleep(1)
        }
        XCTFail("\(title) does not show")
    }

    func testTheHomeShowsTheSatzFolderAndKeepsFavouritesCollectionsAndTrash() throws {
        let app = XCUIApplication.satz(home: home)
        defer { app.terminate() }
        let window = app.windows["home"]
        XCTAssertTrue(window.exists)
        go(window, "home-all", "All Projects")
        let heft = window.descendants(matching: .any)["project-Heft"].firstMatch
        let plakat = window.descendants(matching: .any)["project-Plakat"].firstMatch
        XCTAssertTrue(heft.waitForExistence(timeout: 10))
        XCTAssertTrue(plakat.exists)
        sleep(2)
        shot("home-all", window)

        // A star makes a favourite.
        heft.rightClick()
        app.menuItems["Add to Favourites"].click()
        go(window, "home-starred", "Favourites")
        XCTAssertTrue(heft.waitForExistence(timeout: 5))
        XCTAssertFalse(plakat.exists)

        // A collection takes the poster.
        go(window, "home-all", "All Projects")
        XCTAssertTrue(plakat.waitForExistence(timeout: 5))
        plakat.rightClick()
        app.menuItems["Collections"].click()
        app.menuItems["New Collection…"].click()
        let rename = window.textFields["rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.typeKey("a", modifierFlags: .command)
        rename.typeText("Kunden 2026\r")
        XCTAssertTrue(window.descendants(matching: .any)["collection-Kunden 2026"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(plakat.waitForExistence(timeout: 5))
        XCTAssertFalse(heft.exists)

        // The trash takes it and puts it back.
        plakat.rightClick()
        app.menuItems["Move to Trash"].click()
        XCTAssertFalse(plakat.waitForExistence(timeout: 2))
        go(window, "home-trash", "Trash")
        let trashed = window.descendants(matching: .any)["trashed-Plakat"].firstMatch
        XCTAssertTrue(trashed.waitForExistence(timeout: 5))
        shot("home-trash", window)
        trashed.rightClick()
        app.menuItems["Put Back"].click()
        XCTAssertFalse(trashed.waitForExistence(timeout: 2))
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appending(path: "Satz/Kunden/Plakat.satz").path))

        // The list, then a double click opens the document and closes the home.
        go(window, "home-all", "All Projects")
        window.radioButtons["list.bullet"].click()
        XCTAssertTrue(window.outlines["home-list"].waitForExistence(timeout: 5))
        shot("home-list", window)
        window.radioButtons["square.grid.2x2"].click()
        XCTAssertTrue(heft.waitForExistence(timeout: 5))
        heft.doubleClick()
        let document = app.windows["Heft.satz"]
        XCTAssertTrue(document.waitForExistence(timeout: 30))
        XCTAssertFalse(window.waitForExistence(timeout: 2))
        // It is recent now, and Window ▸ Home brings the home back.
        app.menuBars.menuBarItems["Window"].menus.menuItems["Home"].click()
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        go(window, "home-recent", "Recent")
        XCTAssertTrue(heft.waitForExistence(timeout: 5))
        XCTAssertFalse(plakat.exists)
        // New… opens the start window.
        window.buttons["home-new"].click()
        XCTAssertTrue(app.windows["New Document"].waitForExistence(timeout: 5))
    }

    func shots(_ appearance: String) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)", "-appearance", appearance]
        app.launchEnvironment["SATZ_RESET_SETTINGS"] = "1"
        app.launchEnvironment["SATZ_HOME"] = home.path
        app.launch()
        defer { app.terminate() }
        let window = app.windows["home"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        // The header reads as one element; its plus is at its end.
        window.descendants(matching: .any)["home-new-collection"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).click()
        let rename = window.textFields["rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.typeKey("a", modifierFlags: .command)
        rename.typeText("Kunden\r")
        go(window, "home-all", "All Projects")
        sleep(3)
        shot("\(appearance)-6-home", window)
    }

    func testHomeLight() throws { try shots("light") }
    func testHomeDark() throws { try shots("dark") }
}
