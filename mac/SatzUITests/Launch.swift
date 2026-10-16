import XCTest

extension XCUIApplication {
    /// Launches Satz in English without restoring windows, and closes the open panel
    /// that a document app shows when it starts without a document.
    static func satz() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)"]
        app.launch()
        let panel = app.windows["Open"]
        if panel.waitForExistence(timeout: 3) { panel.buttons["Cancel"].click() }
        return app
    }
}
