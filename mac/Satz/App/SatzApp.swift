import SwiftUI

@main
struct SatzApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { SatzDocument() }) { file in
            DocumentWindow(document: file.document, url: file.fileURL)
        }
        .commands { SatzCommands() }

        Window("Home", id: HomeView.id) {
            HomeView()
        }
        .defaultSize(width: 1100, height: 720)
        // Its item in the Window menu, which SwiftUI adds.
        .keyboardShortcut("h", modifiers: [.command, .control])
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)

        Window("New Document", id: StartView.id) {
            StartView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
        }
    }
}

/// The home window greets an app without documents instead of the open panel.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["SATZ_RESET_SETTINGS"] != nil, let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        Appearance.current.apply()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Shortcut.follow()
        // The UI tests' document.
        if let path = ProcessInfo.processInfo.environment["SATZ_OPEN"] {
            NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { _, _, _ in }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    /// A click on the Dock icon without windows shows the home window, through its menu item.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows, let item = NSApp.mainMenu?.item(keyEquivalent: "h", modifiers: [.command, .control]),
            let menu = item.menu
        {
            menu.performActionForItem(at: menu.index(of: item))
        }
        return false
    }
}

extension NSMenu {
    /// The item, in this menu or its submenus, with this key equivalent.
    func item(keyEquivalent key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem? {
        for item in items {
            if item.keyEquivalent == key, item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == modifiers { return item }
            if let found = item.submenu?.item(keyEquivalent: key, modifiers: modifiers) { return found }
        }
        return nil
    }
}

/// The editor of the document in the key window, for the menu bar.
extension FocusedValues {
    @Entry var editor: Editor?
}
