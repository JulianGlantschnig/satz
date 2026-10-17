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
        _ = editor.found
        _ = editor.showsPreflight
        _ = editor.inks
        _ = editor.previewed
        _ = editor.tool
        _ = editor.vector
        _ = editor.pen?.anchors.count
        _ = editor.placing.count
        _ = editor.cropping
        container.showsRulers = editor.showsRulers
        // The overview covers the canvas, which then takes no clicks.
        container.isHidden = editor.showsOverview
        container.canvas.contentChanged()
    }
}
