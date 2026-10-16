import CoreGraphics
import Observation
import SatzCore
import SwiftUI

/// Pictures of pages and spreads for the page overview, drawn in the background and
/// kept while their display lists, size and colours stay.
@Observable
final class Thumbnails {
    @ObservationIgnored private let editor: Editor
    @ObservationIgnored private var images: [String: CGImage] = [:]
    @ObservationIgnored private var drawing: Set<String> = []
    @ObservationIgnored private var token: UUID?
    /// Bumped when pictures arrive, so that the views showing them update.
    private(set) var generation = 0

    init(editor: Editor) {
        self.editor = editor
        token = editor.scenes.onImagesDecoded { [weak self] in
            // Pictures drawn while an image decoded lack it.
            self?.images.removeAll()
            self?.generation += 1
        }
    }

    /// The picture of `lists` over `sheets` at `height` points, or nil while it is drawn.
    func image(lists: [(id: String, x: Double)], sheets: [Sheet], height: CGFloat, scale: CGFloat) -> CGImage? {
        _ = generation
        let scene = editor.scenes.scene(editor.snapshot, lists: lists, sheets: sheets, pasteboard: false)
        let key = scene.key.joined(separator: "|") + "@\(height)x\(scale)"
        if let image = images[key] { return image }
        guard !drawing.contains(key), let left = sheets.map(\.x).min(), let right = sheets.map({ $0.x + $0.width }).max(),
            let tall = sheets.map(\.height).max(), tall > 0
        else { return nil }
        drawing.insert(key)
        let rect = CGRect(x: left, y: 0, width: right - left, height: tall)
        let px = height * scale / tall
        let painter = editor.scenes.painter
        Self.queue.async {
            let image = scene.draw(rect: rect, scale: px, painter: painter)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.drawing.remove(key)
                if let image {
                    if self.images.count > 400 { self.images.removeAll() }
                    self.images[key] = image
                    self.generation += 1
                }
            }
        }
        return nil
    }

    private static let queue = DispatchQueue(label: "satz.thumbnails", qos: .utility, attributes: .concurrent)
}

/// A picture of the pages `sheets` drawn from `lists`, `height` points tall.
struct Thumb: View {
    let thumbnails: Thumbnails
    let lists: [(id: String, x: Double)]
    let sheets: [Sheet]
    let height: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        let w = (sheets.map { $0.x + $0.width }.max() ?? 1) - (sheets.map(\.x).min() ?? 0)
        let h = sheets.map(\.height).max() ?? 1
        let width = height * w / h
        ZStack {
            Rectangle().fill(.white)
            if let image = thumbnails.image(lists: lists, sheets: sheets, height: height, scale: scale) {
                Image(decorative: image, scale: scale).resizable()
            }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
    }
}
