import AppKit
import SatzCore
import UniformTypeIdentifiers

/// Files dropped on the canvas: documents open, images place where they drop and fonts
/// join the document; see `drop` in `web/src/file.ts`.
extension CanvasView {
    static let fontTypes: [UTType] = [.font]

    private func urls(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        let files = urls(info)
        let usable = files.isEmpty ? Editor.hasImage(info.draggingPasteboard) : files.contains { Self.kind(of: $0) != nil }
        return usable && editor.editing == nil ? .copy : []
    }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        let p = view.toSpread(convert(info.draggingLocation, from: nil))
        let files = urls(info)
        if files.isEmpty {
            guard let image = Editor.pastedImage(info.draggingPasteboard) else { return false }
            editor.placeNow(image.data, name: image.name, at: p)
            return true
        }
        for url in files {
            switch Self.kind(of: url) {
            case .document?:
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            case .image?:
                guard let data = try? Data(contentsOf: url) else {
                    editor.fail(String(localized: "Could not read \(url.lastPathComponent)."))
                    continue
                }
                editor.placeNow(data, name: url.lastPathComponent, at: p)
            case .font?:
                if let data = try? Data(contentsOf: url), let face = editor.addFont(data) {
                    editor.say(String(localized: "Added the font \(face.family)"))
                }
            case nil:
                editor.fail(String(localized: "Could not use \(url.lastPathComponent). Drop a .satz document, a PNG or JPEG image or a font."))
            }
        }
        window?.makeFirstResponder(self)
        return true
    }

    enum Dropped { case document, image, font }

    static func kind(of url: URL) -> Dropped? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .satz) { return .document }
        if Editor.imageTypes.contains(where: type.conforms(to:)) { return .image }
        if fontTypes.contains(where: type.conforms(to:)) { return .font }
        return nil
    }
}
