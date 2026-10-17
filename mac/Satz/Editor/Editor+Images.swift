import AppKit
import SatzCore
import UniformTypeIdentifiers

/// An image waiting to be placed with the next click on the canvas.
struct Placing {
    var hash: String
    var name: String
    /// Its size in pt at 300 ppi, or smaller to fit the page.
    var w: Double
    var h: Double
    /// What follows the pointer until the click.
    var image: CGImage?
}

extension Editor {
    /// The image files that place.
    static let imageTypes: [UTType] = [.png, .jpeg]

    /// Adds a PNG or JPEG file to the images to place, at 300 ppi or smaller to fit the
    /// current page; see `web/src/editor.ts`.
    @discardableResult
    func loadImage(_ data: Data, name: String) -> Bool {
        do {
            let info = try engine.addImage(data)
            let (w, h) = (Double(info.width) * 72 / 300, Double(info.height) * 72 / 300)
            let fit = page.map { min(1, $0.width / w, $0.height / h) } ?? 1
            let image = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            stopEditing()
            tool = .move
            placing.append(Placing(hash: info.hash, name: name, w: w * fit, h: h * fit, image: image))
            return true
        } catch {
            fail(String(localized: "Could not place \(name): \(error.message)."))
            return false
        }
    }

    /// Asks for PNG and JPEG files to place one after the other.
    func placeImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.imageTypes
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Each image follows the pointer until a click places it.")
        let done = { [weak self] (response: NSApplication.ModalResponse) in
            guard response == .OK, let self else { return }
            for url in panel.urls { loadImage(url) }
            canvas?.window?.makeFirstResponder(canvas)
        }
        if let window = canvas?.window {
            panel.beginSheetModal(for: window) { r in MainActor.assumeIsolated { done(r) } }
        } else {
            done(panel.runModal())
        }
    }

    @discardableResult
    func loadImage(_ url: URL) -> Bool {
        do {
            return loadImage(try Data(contentsOf: url), name: url.lastPathComponent)
        } catch {
            fail(String(localized: "Could not place \(url.lastPathComponent): \(error.localizedDescription)."))
            return false
        }
    }

    /// Places the first image waiting with its centre at `c` into `parent`, whose page sits
    /// `dx` right of the spine, and selects it.
    func place(at c: CGPoint, parent: String, dx: Double) {
        guard !placing.isEmpty else { return }
        let i = placing.removeFirst()
        let made = apply(.placeImage(parent: parent, image: i.hash, name: i.name, x: c.x - dx - i.w / 2, y: c.y - i.h / 2, w: i.w, h: i.h))
        select(made)
    }

    /// The one selected layer that shows an image.
    var selectedImage: Node? {
        guard selection.count == 1, let n = selected.first, n.ppi != nil, n.fills.contains(where: { $0.type == .image }) else { return nil }
        return n
    }

    /// Starts or ends cropping the selected image: its handles crop its frame then, and a
    /// drag moves the image inside it.
    func toggleCrop() {
        if cropping != nil {
            cropping = nil
        } else if let n = selectedImage {
            cropping = n.id
        }
    }

    func fitImage(_ fit: ImageFit) {
        guard let n = selectedImage else { return }
        apply(.fitImage(n.id, fit))
    }

    /// How `fitImage` placed the image fill of `fills`: frame first when the frame has the
    /// image's aspect ratio; see `fitOf` in `web/src/Quick.tsx`.
    static func fit(of fills: [Fill]) -> ImageFit? {
        guard let t = fills.first(where: { $0.type == .image })?.transform, t.count == 6 else { return nil }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-4 }
        guard near(t[1], 0), near(t[2], 0), near(t[4], (1 - t[0]) / 2), near(t[5], (1 - t[3]) / 2) else { return nil }
        let (lo, hi) = (min(t[0], t[3]), max(t[0], t[3]))
        return near(lo, 1) && near(hi, 1) ? .frame : near(lo, 1) ? .cover : near(hi, 1) ? .contain : nil
    }

    /// Sets the brightness, contrast and saturation of the image fills of `n`, each in -1...1.
    func adjust(_ n: Node, _ adjust: [Double]) {
        let fills = n.fills.map { f in
            var f = f
            if f.type == .image { f.adjust = adjust }
            return f
        }
        if let json = try? JSON(encoding: fills) { apply(.set(id: n.id, ["fills": json])) }
    }

    /// Moves the image of `n` inside its frame by `d` in the frame's unturned space.
    func moveImage(_ n: Node, by d: CGPoint) {
        guard n.w > 0, n.h > 0 else { return }
        let fills = n.fills.map { f in
            var f = f
            if f.type == .image, f.transform.count == 6 {
                f.transform[4] += d.x / n.w
                f.transform[5] += d.y / n.h
            }
            return f
        }
        if let json = try? JSON(encoding: fills) { apply(.set(id: n.id, ["fills": json])) }
    }

    /// The whole image of `n` placed in the frame box `b`; see `imageBox` in `web/src/Canvas.tsx`.
    static func imageBox(_ n: Node, in b: Box) -> Box? {
        guard let f = n.fills.first(where: { $0.type == .image }), f.transform.count == 6 else { return nil }
        let t = f.transform
        let (a, bb, c, d, tx, ty) = (t[0], t[1], t[2], t[3], t[4], t[5])
        return Box(
            x: b.x + b.w * (tx + min(0, a) + min(0, c)), y: b.y + b.h * (ty + min(0, bb) + min(0, d)),
            w: b.w * (abs(a) + abs(c)), h: b.h * (abs(bb) + abs(d)), rotation: b.rotation)
    }
}

extension Editor {
    /// Places the image `data` at once with its centre at `c` on the spread, or amid the
    /// current page.
    func placeNow(_ data: Data, name: String, at c: CGPoint? = nil) {
        guard loadImage(data, name: name) else { return }
        let page = page
        let c = c ?? page.map { CGPoint(x: $0.x + $0.width / 2, y: $0.height / 2) } ?? .zero
        if let parent = canvas?.parent(at: c) ?? page.map({ ($0.id, $0.x) }) {
            place(at: c, parent: parent.0, dx: parent.1)
        } else {
            placing.removeLast()
        }
    }

    /// Reads image files among the file URLs of a pasteboard.
    private static let imageFiles: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: imageTypes.map(\.identifier),
    ]
    private static let jpeg = NSPasteboard.PasteboardType(UTType.jpeg.identifier)

    /// The pasteboard holds an image or an image file; files of other kinds hold none.
    static func hasImage(_ pb: NSPasteboard = .general) -> Bool {
        if pb.canReadObject(forClasses: [NSURL.self], options: imageFiles) { return true }
        if pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return false }
        return pb.availableType(from: [.png, jpeg, .tiff]) != nil
    }

    /// An image on the pasteboard as PNG or JPEG bytes: a copied image or image file.
    static func pastedImage(_ pb: NSPasteboard = .general) -> (data: Data, name: String)? {
        guard hasImage(pb) else { return nil }
        if let url = (pb.readObjects(forClasses: [NSURL.self], options: imageFiles) as? [URL])?.first {
            return (try? Data(contentsOf: url)).map { ($0, url.lastPathComponent) }
        }
        let name = String(localized: "Pasted image")
        if let data = pb.data(forType: .png) ?? pb.data(forType: jpeg) { return (data, name) }
        if let tiff = pb.data(forType: .tiff), let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            return (png, name)
        }
        return nil
    }
}
