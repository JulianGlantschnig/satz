import AppKit
import SatzCore

/// The canvas: the spread on screen, drawn in tiles in the background, with its bleed,
/// trim, crop marks, layout grids and guides; it pans, zooms and pinches.
final class CanvasView: NSView {
    let editor: Editor
    private let resources = Resources()
    private lazy var painter = Painter(resources: resources)

    private(set) var view = Viewport(x: 0, y: 0, zoom: 1)
    /// The view each spread was left with, as Figma keeps one per page.
    private var views: [String: Viewport] = [:]
    private var shownSpread: String?
    /// The view still fits the spread as it did when it came on screen; resizing fits it again.
    private var fitting = true

    private var scene: CanvasScene?
    /// Decoded display lists by page id, with their version.
    private var decoded: [String: (version: UInt32, ops: [DisplayList.Op], plates: (cmy: [DisplayList.Op], k: [DisplayList.Op])?)] = [:]
    private var inkTable: InkTable?
    private var inkProfile: String??

    /// Tiles at the zoom they were drawn for, and the ones before shown scaled until these fill.
    private var tiles: Tiles?
    private var fallback: Tiles?
    private var settle: Timer?

    var drag: Drag?
    var overlay = Overlay()
    /// Space is down: a drag pans.
    var spaceHeld = false

    /// Runs when the zoom changes, for the zoom field.
    var zoomChanged: ((Double) -> Void)?

    static let edge = Units.mm(20000)

    init(editor: Editor) {
        self.editor = editor
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        resources.decoded = { [weak self] in self?.imagesDecoded() }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("canvas")
        setAccessibilityLabel(String(localized: "Page canvas"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    // MARK: Content

    /// Reads the editor's document again; the tiles stay until new ones replace them.
    func contentChanged() {
        let snapshot = editor.snapshot
        let cmyk = snapshot.colorMode == .cmyk
        if !cmyk {
            inkTable = nil
            inkProfile = nil
        } else if inkTable == nil || inkProfile != .some(snapshot.profile) {
            inkTable = InkTable(pixels: editor.engine.lut(), id: Int.random(in: 1...Int.max))
            if inkProfile != nil { resources.forgetImages() }
            inkProfile = .some(snapshot.profile)
        }
        let lists: [CanvasScene.List] = editor.lists.map { item in
            let version = editor.engine.listVersion(page: item.id)
            if let d = decoded[item.id], d.version == version, (d.plates != nil) == cmyk {
                return CanvasScene.List(id: item.id, x: item.x, version: version, ops: d.ops, plates: d.plates)
            }
            let ops = (try? DisplayList.decode(editor.engine.displayList(page: item.id))) ?? []
            var plates: (cmy: [DisplayList.Op], k: [DisplayList.Op])?
            if cmyk {
                plates = (
                    (try? DisplayList.decode(editor.engine.plate(page: item.id, k: false))) ?? [],
                    (try? DisplayList.decode(editor.engine.plate(page: item.id, k: true))) ?? []
                )
            }
            decoded[item.id] = (version, ops, plates)
            return CanvasScene.List(id: item.id, x: item.x, version: version, ops: ops, plates: plates)
        }
        let live = Set(lists.map(\.id))
        decoded = decoded.filter { live.contains($0.key) }
        for list in lists {
            resources.prepare(list.ops)
            if let plates = list.plates { resources.prepare(plates.cmy + plates.k) }
        }
        let next = CanvasScene(lists: lists, sheets: editor.sheets, pasteboard: true, lut: inkTable)
        let changed = scene?.key != next.key
        scene = next
        if editor.spreadKey != shownSpread {
            if let shownSpread { views[shownSpread] = view }
            shownSpread = editor.spreadKey
            if let saved = views[editor.spreadKey] {
                show(saved)
            } else {
                fit()
            }
        }
        if changed { refreshTiles() }
        needsDisplay = true
    }

    private func imagesDecoded() {
        refreshTiles()
        needsDisplay = true
    }

    /// Draws the tiles anew, showing the old ones until the new ones are there.
    private func refreshTiles() {
        guard let scene, bounds.width > 0 else { return }
        if let tiles, tiles.zoom == view.zoom { fallback = tiles }
        tiles = Tiles(zoom: view.zoom, scale: backingScale, sceneKey: scene.key)
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? 2 }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        tiles = nil
        fallback = nil
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let old = frame.size
        super.setFrameSize(newSize)
        if fitting, newSize.width > 0, newSize.height > 0 {
            fit()
        } else if old.width > 0 {
            // Keep the middle of the view where it was.
            show(Viewport(x: view.x + (newSize.width - old.width) / 2, y: view.y + (newSize.height - old.height) / 2, zoom: view.zoom))
        }
    }

    // MARK: View

    /// Moves the view to `v`, kept near the pages.
    func show(_ v: Viewport) {
        var v = v
        let (cw, ch) = (bounds.width / 2, bounds.height / 2)
        let edge = Self.edge * v.zoom
        v.x = min(max(v.x, cw - edge), cw + edge)
        v.y = min(max(v.y, ch - edge), ch + edge)
        let zoomed = v.zoom != view.zoom
        fitting = false
        view = v
        if zoomed {
            zoomChanged?(v.zoom)
            settle?.invalidate()
            settle = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.settleZoom() }
            }
        }
        needsDisplay = true
    }

    /// Draws the tiles for the zoom the view came to rest at.
    private func settleZoom() {
        guard let tiles, tiles.zoom != view.zoom else { return }
        fallback = tiles
        self.tiles = nil
        needsDisplay = true
    }

    func fit() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        show(.fit(editor.sheets, in: bounds.size))
        fitting = true
    }

    func zoom(to zoom: Double, around p: CGPoint? = nil) {
        show(view.zoomed(to: zoom, around: p ?? CGPoint(x: bounds.midX, y: bounds.midY)))
    }

    /// Steps of the zoom menu and the zoom in and out commands.
    static let steps: [Double] = [0.0625, 0.125, 0.25, 0.333, 0.5, 0.667, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 32, 64, 128, 256]

    func zoomIn() { zoom(to: Self.steps.first { $0 > view.zoom * 1.001 } ?? Viewport.maxZoom) }
    func zoomOut() { zoom(to: Self.steps.last { $0 < view.zoom / 1.001 } ?? Viewport.minZoom) }

    /// Fits `box` of the spread into the view.
    func zoom(toFit box: CGRect) { show(.fit(box, in: bounds.size)) }

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let precise = event.hasPreciseScrollingDeltas
        let (dx, dy) = (event.scrollingDeltaX * (precise ? 1 : 16), event.scrollingDeltaY * (precise ? 1 : 16))
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            zoom(to: view.zoom * exp(dy * 0.01), around: p)
        } else {
            show(Viewport(x: view.x + dx, y: view.y + dy, zoom: view.zoom))
        }
    }

    override func magnify(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        zoom(to: view.zoom * (1 + event.magnification), around: p)
    }

    override func smartMagnify(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let fit = Viewport.fit(editor.sheets, in: bounds.size)
        if abs(view.zoom - fit.zoom) / fit.zoom < 0.05 {
            zoom(to: fit.zoom * 2.5, around: p)
        } else {
            show(fit)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.underPageBackgroundColor.cgColor)
        ctx.fill(dirtyRect)
        guard let scene else { return }
        if tiles == nil {
            tiles = Tiles(zoom: view.zoom, scale: backingScale, sceneKey: scene.key)
        }
        guard let tiles else { return }
        // The part of the zoomed spread on screen, in the tiles' space.
        let visible = CGRect(x: -view.x, y: -view.y, width: bounds.width, height: bounds.height)
        let factor = view.zoom / tiles.zoom
        let keys = Tiles.keys(covering: CGRect(
            x: visible.minX / factor, y: visible.minY / factor, width: visible.width / factor, height: visible.height / factor))
        tiles.request(keys, scene: scene, painter: painter) { [weak self] in self?.needsDisplay = true }
        tiles.prune(keeping: keys)

        ctx.saveGState()
        ctx.interpolationQuality = .medium
        if let fallback, !tiles.has(keys) { drawTiles(fallback, ctx) }
        drawTiles(tiles, ctx)
        ctx.restoreGState()
        if tiles.has(keys) { fallback = nil }

        drawChrome(ctx)
        drawOverlay(ctx)
    }

    private func drawTiles(_ t: Tiles, _ ctx: CGContext) {
        let f = view.zoom / t.zoom
        for (key, image) in t.images {
            let side = Tiles.size * f
            let rect = CGRect(x: view.x + CGFloat(key.x) * side, y: view.y + CGFloat(key.y) * side, width: side, height: side)
            guard rect.intersects(bounds) else { continue }
            ctx.saveGState()
            // The view is flipped; images draw upright in y-up space.
            ctx.translateBy(x: rect.minX, y: rect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
            ctx.restoreGState()
        }
    }

    private static let bleedColor = CGColor(srgbRed: 56 / 255, green: 174 / 255, blue: 224 / 255, alpha: 0.45)
    private static let cropColor = CGColor(srgbRed: 128 / 255, green: 131 / 255, blue: 139 / 255, alpha: 1)
    private static let gridColor = (r: 1.0, g: 72 / 255.0, b: 72 / 255.0)
    private static let guideColor = CGColor(srgbRed: 0, green: 170 / 255, blue: 1, alpha: 0.9)

    /// The bleed, trim, crop marks, and when they are on the layout grids and guides.
    private func drawChrome(_ ctx: CGContext) {
        let sheets = editor.sheets
        guard !sheets.isEmpty else { return }
        let z = view.zoom
        ctx.saveGState()
        ctx.translateBy(x: view.x, y: view.y)
        ctx.scaleBy(x: z, y: z)
        ctx.setLineWidth(1 / z)

        if editor.showsGrids {
            for s in sheets {
                let spans = s.gridSpans()
                for span in spans.x {
                    let r = CGRect(x: span.from, y: span.margin, width: span.to - span.from, height: s.height - 2 * span.margin)
                    drawSpan(r, line: span.from == span.to, ctx)
                }
                for span in spans.y {
                    let r = CGRect(x: s.x + span.margin, y: span.from, width: s.width - 2 * span.margin, height: span.to - span.from)
                    drawSpan(r, line: span.from == span.to, ctx)
                }
            }
            ctx.setStrokeColor(Self.guideColor)
            let far = 1e5
            for s in sheets {
                for x in s.guides.x { ctx.strokeLineSegments(between: [CGPoint(x: s.x + x, y: -far), CGPoint(x: s.x + x, y: far)]) }
                for y in s.guides.y { ctx.strokeLineSegments(between: [CGPoint(x: -far, y: y), CGPoint(x: far, y: y)]) }
            }
        }

        let bleed = CGMutablePath()
        for s in sheets { bleed.addRect(s.bleedBox) }
        ctx.setStrokeColor(Self.bleedColor)
        ctx.setLineDash(phase: 0, lengths: [4 / z, 3 / z])
        // The outline of the union of the bleed boxes.
        ctx.addPath(bleed.normalized())
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(Self.cropColor)
        for s in sheets { ctx.stroke(s.trim) }
        let l = sheets[0].x
        let r = sheets.map { $0.x + $0.width }.max()!
        let b = sheets.map(\.height).max()!
        let off = sheets.map(\.bleed).max()! + 4 / z
        let len = 14 / z
        for (x, y, dx, dy) in [(l, 0.0, -1.0, -1.0), (r, 0, 1, -1), (l, b, -1, 1), (r, b, 1, 1)] {
            ctx.strokeLineSegments(between: [
                CGPoint(x: x + dx * off, y: y), CGPoint(x: x + dx * (off + len), y: y),
                CGPoint(x: x, y: y + dy * off), CGPoint(x: x, y: y + dy * (off + len)),
            ])
        }
        ctx.restoreGState()
    }

    private func drawSpan(_ r: CGRect, line: Bool, _ ctx: CGContext) {
        let c = Self.gridColor
        if line {
            ctx.setStrokeColor(CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 0.3))
            ctx.strokeLineSegments(between: [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY)])
        } else {
            ctx.setFillColor(CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 0.12))
            ctx.fill(r)
        }
    }
}
