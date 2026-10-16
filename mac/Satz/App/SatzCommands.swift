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

        CommandMenu("Object") {
            let none = editor?.selection.isEmpty ?? true
            Button("Duplicate") { editor.map { $0.duplicate($0.selection) } }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(none)
            Divider()
            Button("Group") { editor?.group() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(none)
            Button("Group as Frame") { editor?.group(frame: true) }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(none)
            Button("Ungroup") { editor?.ungroup() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(none)
            Button("Use as Mask") { editor?.mask() }
                .keyboardShortcut("m", modifiers: [.command, .option])
                .disabled(none)
            Divider()
            Button("Bring to Front") { editor?.order(.front) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(none)
            Button("Bring Forward") { editor?.order(.forward) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(none)
            Button("Send Backward") { editor?.order(.backward) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(none)
            Button("Send to Back") { editor?.order(.back) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(none)
            Divider()
            Button("Flip Horizontal") { editor?.flip(vertical: false) }
                .disabled(none)
            Button("Flip Vertical") { editor?.flip(vertical: true) }
                .disabled(none)
            Divider()
            Button("Show or Hide") { editor?.toggle("hidden") }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(none)
            Button("Lock or Unlock") { editor?.toggle("locked") }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(none)
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
