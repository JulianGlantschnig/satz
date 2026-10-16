import SwiftUI

/// The menu bar. Undo and redo come from the window's undo manager, which the
/// editor feeds; see `Editor.registerUndo`.
struct SatzCommands: Commands {
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In") { editor?.canvas?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { editor?.canvas?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Zoom to 100%") { editor?.canvas?.zoom(to: 1) }
                .keyboardShortcut("0", modifiers: .command)
            Button("Zoom to Fit") { editor?.canvas?.fit() }
                .keyboardShortcut("1", modifiers: .shift)
            Divider()
            Button(editor?.showsGrids == true ? "Hide Layout Grids" : "Show Layout Grids") {
                editor?.showsGrids.toggle()
            }
            .keyboardShortcut("g", modifiers: .shift)
            Divider()
        }

        CommandMenu("Page") {
            Button("Add Page") { editor?.addPage() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Duplicate Page") { editor?.duplicatePage() }
                .disabled(editor?.isMaster ?? true)
            Button("Delete Page") { editor?.deletePage() }
                .disabled(editor.map { $0.isMaster || $0.snapshot.pages.count < 2 } ?? true)
            Divider()
            Button("Next Spread") { editor?.nextSpread() }
                .keyboardShortcut(.pageDown, modifiers: [])
            Button("Previous Spread") { editor?.previousSpread() }
                .keyboardShortcut(.pageUp, modifiers: [])
            Button("First Spread") { editor?.firstSpread() }
                .keyboardShortcut(.home, modifiers: [])
            Button("Last Spread") { editor?.lastSpread() }
                .keyboardShortcut(.end, modifiers: [])
        }
    }
}
