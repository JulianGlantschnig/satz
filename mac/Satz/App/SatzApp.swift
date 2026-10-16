import SwiftUI

@main
struct SatzApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { SatzDocument() }) { file in
            DocumentWindow(document: file.document)
        }
        .commands { SatzCommands() }
    }
}

/// The editor of the document in the key window, for the menu bar.
extension FocusedValues {
    @Entry var editor: Editor?
}
