import SatzCore
import SwiftUI

/// The canvas in SwiftUI. It reads the snapshot here, so that every change of the
/// document reaches it.
struct Canvas: NSViewRepresentable {
    let editor: Editor

    func makeNSView(context: Context) -> CanvasContainer {
        let view = CanvasView(editor: editor)
        editor.canvas = view
        view.zoomChanged = { zoom in editor.zoom = zoom }
        return CanvasContainer(canvas: view)
    }

    func updateNSView(_ container: CanvasContainer, context: Context) {
        // Reading these makes SwiftUI call this again when they change.
        _ = editor.snapshot
        _ = editor.pageID
        _ = editor.showsGrids
        _ = editor.selection
        _ = editor.hover
        _ = editor.guide
        _ = editor.editing
        _ = editor.threading
        container.showsRulers = editor.showsRulers
        container.canvas.contentChanged()
    }
}
