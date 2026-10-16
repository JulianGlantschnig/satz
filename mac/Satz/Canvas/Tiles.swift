import CoreGraphics
import Foundation
import SatzCore

/// What the canvas draws of a spread: each page's display list at its x on the spread,
/// the pages' paper, and whether layers beyond the bleed show.
nonisolated struct CanvasScene: Sendable {
    struct List: Sendable {
        var id: String
        var x: Double
        var version: UInt32
        var ops: [DisplayList.Op]
        /// The C, M and Y plate and the K plate, for CMYK documents.
        var plates: (cmy: [DisplayList.Op], k: [DisplayList.Op])?
    }

    var lists: [List]
    var sheets: [Sheet]
    var pasteboard: Bool
    /// The screen colours of CMYK on a grid of `lut.size` steps per ink, when the
    /// document blends in CMYK.
    var lut: InkTable?

    /// Changes whenever what the scene draws does.
    var key: [String] {
        lists.map { "\($0.id)@\($0.x)#\($0.version)" } + sheets.map { "\($0.x),\($0.width),\($0.height),\($0.bleed)" }
            + ["\(pasteboard)", "\(lut?.id ?? 0)"]
    }

    /// Draws the scene's part `rect` of the spread into `ctx`, whose user space is the spread's.
    func draw(rect: CGRect, scale: CGFloat, painter: Painter) -> CGImage? {
        let w = Int((rect.width * scale).rounded())
        let h = Int((rect.height * scale).rounded())
        if let lut {
            guard let cmy = plate(rect: rect, scale: scale, w: w, h: h, painter: painter, k: false),
                let k = plate(rect: rect, scale: scale, w: w, h: h, painter: painter, k: true)
            else { return nil }
            return lut.combine(cmy: cmy, k: k)
        }
        guard let ctx = Raster.context(rect: rect, scale: scale, width: w, height: h) else { return nil }
        paint(ctx, painter: painter) { $0.ops }
        return ctx.makeImage()
    }

    /// A plate drawn as `paint` draws the page, on white paper.
    private func plate(rect: CGRect, scale: CGFloat, w: Int, h: Int, painter: Painter, k: Bool) -> CGImage? {
        guard let ctx = Raster.context(rect: rect, scale: scale, width: w, height: h) else { return nil }
        paint(ctx, painter: painter) { k ? ($0.plates?.k ?? []) : ($0.plates?.cmy ?? []) }
        return ctx.makeImage()
    }

    private func paint(_ ctx: CGContext, painter: Painter, ops: (List) -> [DisplayList.Op]) {
        ctx.setFillColor(.white)
        for s in sheets { ctx.fill(s.trim) }
        ctx.saveGState()
        if !pasteboard {
            for s in sheets { ctx.addRect(s.bleedBox) }
            ctx.clip()
        }
        for list in lists {
            ctx.saveGState()
            ctx.translateBy(x: list.x, y: 0)
            painter.draw(ops(list), in: ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }
}

/// Square tiles of the canvas at one zoom, drawn in the background.
@MainActor
final class Tiles {
    /// The side of a tile in canvas points.
    static let size: CGFloat = 512

    struct Key: Hashable {
        var x: Int
        var y: Int
    }

    let zoom: Double
    let scale: CGFloat
    let sceneKey: [String]
    private(set) var images: [Key: CGImage] = [:]
    private var asked: Set<Key> = []
    /// Bumped to drop the tiles still being drawn.
    private var generation = 0

    init(zoom: Double, scale: CGFloat, sceneKey: [String]) {
        self.zoom = zoom
        self.scale = scale
        self.sceneKey = sceneKey
    }

    /// The tiles that cover `rect` of the zoomed spread, whose origin is the spread's.
    static func keys(covering rect: CGRect) -> [Key] {
        guard !rect.isNull, !rect.isEmpty else { return [] }
        let x0 = Int((rect.minX / size).rounded(.down))
        let x1 = Int((rect.maxX / size).rounded(.up))
        let y0 = Int((rect.minY / size).rounded(.down))
        let y1 = Int((rect.maxY / size).rounded(.up))
        guard x1 - x0 < 64, y1 - y0 < 64 else { return [] }
        return (y0..<y1).flatMap { y in (x0..<x1).map { Key(x: $0, y: y) } }
    }

    /// The part of the spread that the tile `key` shows.
    func spreadRect(_ key: Key) -> CGRect {
        let s = Self.size / zoom
        return CGRect(x: CGFloat(key.x) * s, y: CGFloat(key.y) * s, width: s, height: s)
    }

    /// Draws the missing tiles of `keys` in the background; `done` runs as each arrives.
    func request(_ keys: [Key], scene: CanvasScene, painter: Painter, done: @escaping @MainActor () -> Void) {
        let generation = self.generation
        for key in keys where images[key] == nil && !asked.contains(key) {
            asked.insert(key)
            let rect = spreadRect(key)
            let scale = CGFloat(zoom) * self.scale
            Self.queue.async {
                let image = scene.draw(rect: rect, scale: scale, painter: painter)
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else { return }
                    self.asked.remove(key)
                    if let image { self.images[key] = image }
                    done()
                }
            }
        }
    }

    /// Forgets the tiles, as when an image decoded that they lack.
    func clear() {
        generation += 1
        images.removeAll()
        asked.removeAll()
    }

    func has(_ keys: [Key]) -> Bool { keys.allSatisfy { images[$0] != nil } }

    /// Forgets the tiles beyond `limit` that are not among `keep`, those farthest away first.
    func prune(keeping keep: [Key], limit: Int = 96) {
        guard images.count > limit, let first = keep.first else { return }
        let kept = Set(keep)
        let far = images.keys.filter { !kept.contains($0) }
            .sorted { abs($0.x - first.x) + abs($0.y - first.y) > abs($1.x - first.x) + abs($1.y - first.y) }
        for key in far.prefix(images.count - limit) { images[key] = nil }
    }

    private static let queue = DispatchQueue(label: "satz.tiles", qos: .userInitiated, attributes: .concurrent)
}
