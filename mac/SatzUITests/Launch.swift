import XCTest

extension XCUIApplication {
    /// Launches Satz in English without restoring windows and with its first settings.
    /// It greets with the start window, which closes when a document opens, or opens
    /// the document at `url` at once.
    static func satz(opening url: URL? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)"]
        // Each test starts from the settings an app has at first.
        app.launchEnvironment["SATZ_RESET_SETTINGS"] = "1"
        // Not through `open(_:)`, which may start a second Satz.
        if let url { app.launchEnvironment["SATZ_OPEN"] = url.path }
        app.launch()
        // The menus take clicks once the app shows its first window.
        if url == nil { _ = app.windows["New Document"].waitForExistence(timeout: 30) }
        return app
    }
}

extension XCUIElement {
    /// Shows the "Pages" or "Layers" tab of the window's sidebar.
    func showSidebar(_ tab: String) {
        let button = radioButtons[tab].firstMatch
        if button.waitForExistence(timeout: 5), !button.isSelected { button.click() }
    }
}
