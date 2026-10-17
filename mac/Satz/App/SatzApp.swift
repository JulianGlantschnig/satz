import SwiftUI

@main
struct SatzApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { SatzDocument() }) { file in
            DocumentWindow(document: file.document)
        }
        .commands { SatzCommands() }

        Window("New Document", id: StartView.id) {
            StartView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)

        Settings {
            SettingsView()
        }
    }
}

/// The start window greets an app without documents instead of the open panel.
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
}

/// The editor of the document in the key window, for the menu bar.
extension FocusedValues {
    @Entry var editor: Editor?
}
