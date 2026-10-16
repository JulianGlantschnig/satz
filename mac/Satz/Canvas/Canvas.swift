import SatzCore
import SwiftUI

/// The canvas in SwiftUI. It reads the snapshot here, so that every change of the
/// document reaches it.
struct Canvas: NSViewRepresentable {
    let editor: Editor

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView(editor: editor)
        editor.canvas = view
        view.zoomChanged = { zoom in editor.zoom = zoom }
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        // Reading these makes SwiftUI call this again when they change.
        _ = editor.snapshot
        _ = editor.pageID
        _ = editor.showsGrids
        view.contentChanged()
    }
}
