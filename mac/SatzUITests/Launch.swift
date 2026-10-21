import XCTest

extension XCUIApplication {
    /// Launches Satz in English without restoring windows and with its first settings.
    /// It greets with the home window, which closes when a document opens, or opens the
    /// document at `url` at once. The home window shows the documents of `home`, a folder
    /// of the test's own, so that it never touches the user's.
    static func satz(opening url: URL? = nil, home: URL? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)"]
        // Each test starts from the settings an app has at first.
        app.launchEnvironment["SATZ_RESET_SETTINGS"] = "1"
        app.launchEnvironment["SATZ_HOME"] = (home ?? FileManager.default.temporaryDirectory.appending(path: "satz-home-\(UUID().uuidString)")).path
        // Not through `open(_:)`, which may start a second Satz.
        if let url { app.launchEnvironment["SATZ_OPEN"] = url.path }
        app.launch()
        // The menus take clicks once the app shows its first window.
        if url == nil { _ = app.windows["home"].waitForExistence(timeout: 30) }
        return app
    }

    /// Opens the start window through File ▸ New from Format….
    func openStart() -> XCUIElement {
        menuBars.menuBarItems["File"].menus.menuItems["New from Format…"].click()
        let start = windows["New Document"]
        _ = start.waitForExistence(timeout: 10)
        return start
    }
}

extension XCUIElement {
    /// Shows the "Pages" or "Layers" tab of the window's sidebar.
    func showSidebar(_ tab: String) {
        let button = radioButtons[tab].firstMatch
        if button.waitForExistence(timeout: 5), !button.isSelected { button.click() }
    }
}
