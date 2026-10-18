import CoreGraphics
import Foundation

/// A page on the canvas: its trim size and bleed, and the x of its left edge on its spread.
public struct Sheet: Equatable, Sendable {
    public var id: String
    public var x: Double
    public var width: Double
    public var height: Double
    public var bleed: Double
    public var grids: [Grid]
    public var guides: Guides
    /// The raster among the layout grids, the page's own or its master's.
    public var raster: RasterGrid.Spec?
    /// A left page, whose raster mirrors its holes and header to the spine on the right.
    public var mirrored: Bool

    public init(
        id: String, x: Double, width: Double, height: Double, bleed: Double, grids: [Grid] = [], guides: Guides = Guides(),
        raster: RasterGrid.Spec? = nil, mirrored: Bool = false
    ) {
        self.id = id
        self.x = x
        self.width = width
        self.height = height
        self.bleed = bleed
        self.grids = grids
        self.guides = guides
        self.raster = raster ?? grids.lazy.compactMap(\.spec).first
        self.mirrored = mirrored
    }

    public init(_ page: Page, x: Double? = nil, master: Page? = nil) {
        let raster = page.grids.lazy.compactMap(\.spec).first ?? master?.grids.lazy.compactMap(\.spec).first
        self.init(
            id: page.id, x: x ?? page.x, width: page.width, height: page.height, bleed: page.bleed, grids: page.grids,
            guides: page.guides, raster: raster, mirrored: page.side == .left)
    }

    /// The area of the raster on the spread, between the margins of its spec.
    public var rasterArea: CGRect? {
        guard let r = raster else { return nil }
        let mm = 72 / 25.4
        let (left, right) = mirrored ? (r.marginRight, r.marginLeft) : (r.marginLeft, r.marginRight)
        let area = CGRect(x: x + left * mm, y: r.marginTop * mm, width: width - (left + right) * mm, height: height - (r.marginTop + r.marginBottom) * mm)
        return area.width > 0 && area.height > 0 ? area : nil
    }

    public var trim: CGRect { CGRect(x: x, y: 0, width: width, height: height) }
    public var bleedBox: CGRect { trim.insetBy(dx: -bleed, dy: -bleed) }

    /// The columns and rows of its layout grids as spans on their axis in the space of
    /// the spread, with the margin across them; the lines of a grid span nothing.
    public func gridSpans() -> (x: [GridSpan], y: [GridSpan]) {
        var xs: [GridSpan] = []
        var ys: [GridSpan] = []
        let epsilon = 1e-6
        for g in grids where g.kind != .raster {
            if g.kind == .grid {
                guard g.size > 0 else { continue }
                var at = g.size
                while at < width - epsilon {
                    xs.append(GridSpan(from: x + at, to: x + at, margin: 0))
                    at += g.size
                }
                at = g.size
                while at < height - epsilon {
                    ys.append(GridSpan(from: at, to: at, margin: 0))
                    at += g.size
                }
                continue
            }
            guard g.count > 0 else { continue }
            let (length, start) = g.kind == .columns ? (width, x) : (height, 0)
            let size = (length - 2 * g.margin - g.gutter * Double(g.count - 1)) / Double(g.count)
            for i in 0..<g.count {
                let at = start + g.margin + Double(i) * (size + g.gutter)
                let span = GridSpan(from: at, to: at + size, margin: g.margin)
                if g.kind == .columns { xs.append(span) } else { ys.append(span) }
            }
        }
        return (xs, ys)
    }
}

public struct GridSpan: Equatable, Sendable {
    public var from: Double
    public var to: Double
    /// How far it stays from the page's edges across its axis.
    public var margin: Double
}

/// How the spread maps to the canvas: a point p of the spread shows at
/// `origin + p * zoom` in the canvas's points.
public struct Viewport: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var zoom: Double

    public static let minZoom = 0.02
    public static let maxZoom = 256.0

    public init(x: Double, y: Double, zoom: Double) {
        self.x = x
        self.y = y
        self.zoom = zoom
    }

    public func toCanvas(_ p: CGPoint) -> CGPoint { CGPoint(x: x + p.x * zoom, y: y + p.y * zoom) }
    public func toSpread(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - x) / zoom, y: (p.y - y) / zoom) }

    /// The view at `zoom` that keeps the canvas point `p` where it is.
    public func zoomed(to zoom: Double, around p: CGPoint) -> Viewport {
        let z = min(Self.maxZoom, max(Self.minZoom, zoom))
        return Viewport(x: p.x - (p.x - x) * z / self.zoom, y: p.y - (p.y - y) * z / self.zoom, zoom: z)
    }

    /// The view that fits `sheets` with their bleed into `size` and centres them.
    public static func fit(_ sheets: [Sheet], in size: CGSize, padding: Double = 64) -> Viewport {
        guard !sheets.isEmpty, size.width > 0, size.height > 0 else { return Viewport(x: 0, y: 0, zoom: 1) }
        let left = sheets.map(\.x).min()!
        let w = sheets.map { $0.x + $0.width }.max()! - left
        let h = sheets.map(\.height).max()!
        let bleed = sheets.map(\.bleed).max()!
        let pad = min(padding, size.width / 12, size.height / 12)
        let zoom = min((size.width - 2 * pad) / (w + 2 * bleed), (size.height - 2 * pad) / (h + 2 * bleed))
        return Viewport(x: (size.width - w * zoom) / 2 - left * zoom, y: (size.height - h * zoom) / 2, zoom: zoom)
    }

    /// The view that shows `box` of the spread as large as fits into `size`.
    public static func fit(_ box: CGRect, in size: CGSize, padding: Double = 64) -> Viewport {
        guard box.width > 0 || box.height > 0, size.width > 0, size.height > 0 else { return Viewport(x: 0, y: 0, zoom: 1) }
        let pad = min(padding, size.width / 12, size.height / 12)
        let zoom = min(Self.maxZoom, min((size.width - 2 * pad) / max(box.width, 1e-3), (size.height - 2 * pad) / max(box.height, 1e-3)))
        return Viewport(x: size.width / 2 - box.midX * zoom, y: size.height / 2 - box.midY * zoom, zoom: zoom)
    }
}
