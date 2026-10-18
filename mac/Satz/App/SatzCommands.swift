import SatzCore
import SwiftUI

/// The menu bar. Undo and redo come from the window's undo manager, which the
/// editor feeds; see `Editor.registerUndo`.
struct SatzCommands: Commands {
    /// The keys of the booleans with ⌥⌘, as in the web app.
    static let booleanKeys: [BooleanOp: String] = [.union: "u", .subtract: "s", .intersect: "i", .exclude: "x"]

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
            Button("Deselect All") { editor?.select([]) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(editor?.selection.isEmpty ?? true)
            Divider()
            Button("Copy Style") { editor?.copyStyle() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(editor?.selection.isEmpty ?? true)
            Button("Paste Style") { editor?.pasteStyle() }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(editor?.selection.isEmpty ?? true || editor?.copiedStyle == nil)
            Divider()
            Button("Find and Replace…") { editor?.showsFind = true }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(editor == nil)
            // ⌘G finds the next match while the find bar shows, else it groups.
            let finding = editor?.showsFind == true
            Button("Find Next") { editor?.findStep(1) }
                .keyboardShortcut(finding ? KeyboardShortcut("g", modifiers: .command) : nil)
                .disabled(editor?.found.isEmpty ?? true)
            Button("Find Previous") { editor?.findStep(-1) }
                .keyboardShortcut(finding ? KeyboardShortcut("g", modifiers: [.command, .shift]) : nil)
                .disabled(editor?.found.isEmpty ?? true)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button("Command Palette…") { editor?.showsPalette.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(editor == nil)
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
            Button(editor?.showsPanels == false ? "Show Panels" : "Hide Panels") { editor?.showsPanels.toggle() }
                .disabled(editor == nil)
            Button(editor?.showsRulers == true ? "Hide Rulers" : "Show Rulers") {
                editor?.showsRulers.toggle()
            }
            .keyboardShortcut("r", modifiers: .command)
            Button(editor?.showsGrids == true ? "Hide Layout Grids and Guides" : "Show Layout Grids and Guides") {
                editor?.showsGrids.toggle()
            }
            .keyboardShortcut(";", modifiers: .command)
            Button(editor?.showsNonprinting == false ? "Show Nonprinting Layers" : "Hide Nonprinting Layers") {
                editor?.showsNonprinting.toggle()
            }
            .keyboardShortcut(";", modifiers: [.command, .option])
            .disabled(editor == nil)
            Divider()
        }

        CommandMenu("Object") {
            let none = editor?.selection.isEmpty ?? true
            Button("Duplicate") { editor.map { $0.duplicate($0.selection) } }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(none)
            Divider()
            let finding = editor?.showsFind == true
            Button("Group") { editor?.group() }
                .keyboardShortcut(finding ? nil : KeyboardShortcut("g", modifiers: .command))
                .disabled(none)
            Button("Group as Frame") { editor?.group(frame: true) }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(none)
            Button("Ungroup") { editor?.ungroup() }
                .keyboardShortcut(finding ? nil : KeyboardShortcut("g", modifiers: [.command, .shift]))
                .disabled(none)
            Button("Use as Mask") { editor?.mask() }
                .keyboardShortcut("m", modifiers: [.command, .option])
                .disabled(none)
            Divider()
            Menu("Align") {
                ForEach(Editor.Align.allCases) { a in
                    Button(String(localized: a.title)) { editor?.align(a) }
                }
            }
            .disabled(none)
            Menu("Boolean") {
                ForEach(BooleanOp.allCases, id: \.self) { op in
                    Button(ArrangeSection.title(op)) { editor?.combine(op) }
                        .keyboardShortcut(KeyEquivalent(Character(Self.booleanKeys[op]!)), modifiers: [.command, .option])
                }
            }
            .disabled(!(editor?.combinable ?? false))
            Button("Flatten") { editor?.flatten() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!(editor?.selected.contains { $0.kind == .text || $0.kind == .shape } ?? false))
            Button("Fit Frame to Text") { editor?.fitText() }
                .keyboardShortcut("c", modifiers: [.command, .option, .control])
                .disabled(!(editor?.hasText ?? false))
            Button("Auto Height") { editor?.fitText(height: true) }
                .keyboardShortcut("h", modifiers: [.command, .option, .control])
                .disabled(!(editor?.hasText ?? false))
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

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { editor?.showsShortcuts = true }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(editor == nil)
        }
    }
}
