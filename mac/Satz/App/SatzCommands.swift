import SwiftUI

/// The menu bar. Undo and redo come from the window's undo manager, which the
/// editor feeds; see `Editor.registerUndo`.
struct SatzCommands: Commands {
    @FocusedValue(\.editor) private var editor
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New from Format…") { openWindow(id: StartView.id) }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandGroup(after: .importExport) {
            Button("Place Image…") { editor?.placeImages() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Divider()
            Button("Export…") { editor?.openExport() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Button(editor?.showsPreflight == true ? "Close Preflight" : "Preflight") { editor?.togglePreflight() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(editor == nil)
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { editor?.printDocument() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(editor == nil || editor?.exporting == true)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find and Replace…") { editor?.showsFind = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(editor == nil)
            Button("Find Next") { editor?.findStep(1) }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(editor?.found.isEmpty ?? true)
            Button("Find Previous") { editor?.findStep(-1) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(editor?.found.isEmpty ?? true)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In") { editor?.canvas?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { editor?.canvas?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Zoom to 100%") { editor?.canvas?.zoom(to: 1) }
                .keyboardShortcut("0", modifiers: .command)
            Button("Zoom to Fit") { editor?.canvas?.fit() }
                .keyboardShortcut("1", modifiers: .command)
            Button("Zoom to Selection") { editor?.canvas?.zoomToSelection() }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(editor?.selection.isEmpty ?? true)
            Divider()
            Button(editor?.showsRulers == true ? "Hide Rulers" : "Show Rulers") {
                editor?.showsRulers.toggle()
            }
            .keyboardShortcut("r", modifiers: .command)
            Button(editor?.showsGrids == true ? "Hide Layout Grids and Guides" : "Show Layout Grids and Guides") {
                editor?.showsGrids.toggle()
            }
            .keyboardShortcut(";", modifiers: .command)
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
            Button("Edit Points") { editor.map { e in e.selected.first.map { e.editPath($0.id) } } }
                .disabled(!(editor?.selected.count == 1 && editor?.selected.first?.kind == .shape && editor?.vector == nil))
            Divider()
            Button("Add Auto Layout") { editor?.addAutoLayout() }
                .disabled(none)
            Button("Remove Auto Layout") { editor?.removeAutoLayout() }
                .disabled(!(editor?.selected.contains { $0.kind == .frame && $0.direction != .none } ?? false))
            Divider()
            let image = editor?.selectedImage == nil
            Button(editor?.cropping == nil ? "Crop Image" : "Done Cropping") { editor?.toggleCrop() }
                .disabled(image)
            Menu("Fit Image") {
                ForEach(ImageSection.fits, id: \.0) { f in
                    Button(f.1) { editor?.fitImage(f.0) }
                }
            }
            .disabled(image)
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
            Button(editor?.showsOverview == true ? "Close Page Overview" : "Page Overview") { editor?.toggleOverview() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Add Page") { editor?.addPage() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Duplicate Page") { editor?.duplicatePage() }
            Button("Delete Page") { editor?.deletePage() }
                .disabled(editor.map { $0.snapshot.pages.count < 2 } ?? true)
            Divider()
            Button("New Master from Page") { editor.map { $0.addMaster(like: $0.pageOrLast, layers: true) } }
            Button("Leave Master") { editor?.exitMaster() }
                .disabled(editor?.master == nil)
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
