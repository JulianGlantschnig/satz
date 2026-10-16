import SwiftUI

/// The menu bar. Undo and redo come from the window's undo manager, which the
/// editor feeds; see `Editor.registerUndo`.
struct SatzCommands: Commands {
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        CommandMenu("Page") {
            Button("Add Page") { editor?.addPage() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Duplicate Page") { editor?.duplicatePage() }
                .disabled(editor?.isMaster ?? true)
            Button("Delete Page") { editor?.deletePage() }
                .disabled(editor.map { $0.isMaster || $0.snapshot.pages.count < 2 } ?? true)
        }
    }
}
