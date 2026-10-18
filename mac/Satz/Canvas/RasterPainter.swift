import AppKit
import CoreText
import SatzCore

/// Draws a raster of `RasterGrid` with Core Graphics: on the canvas among the layout grids
/// and in the preview of the raster window. Rasters are built once per spec and size.
@MainActor
enum RasterPainter {
    private struct Key: Hashable {
        var spec: String
        var width, height: Double
        var mirrored: Bool
    }

    private struct Built {
        var strokes: [(stroke: RasterGrid.Stroke, path: CGPath, color: CGColor)]
        var labels: [RasterGrid.Label]
    }

    private static var cache: [Key: Built] = [:]

    private static func built(_ spec: RasterGrid.Spec, width: Double, height: Double, mirrored: Bool) -> Built {
        let key = Key(spec: spec.json, width: width, height: height, mirrored: mirrored)
        if let b = cache[key] { return b }
        let d = RasterGrid.build(spec, width: width, height: height, mirrored: mirrored)
        let strokes = d.strokes.map { s -> (RasterGrid.Stroke, CGPath, CGColor) in
            let path = CGMutablePath()
            let p = s.path
            var i = 0
            while i < p.count {
                switch p[i] {
                case 0: path.move(to: CGPoint(x: p[i + 1], y: p[i + 2])); i += 3
                case 1: path.addLine(to: CGPoint(x: p[i + 1], y: p[i + 2])); i += 3
                case 4:
                    path.addCurve(
                        to: CGPoint(x: p[i + 5], y: p[i + 6]), control1: CGPoint(x: p[i + 1], y: p[i + 2]),
                        control2: CGPoint(x: p[i + 3], y: p[i + 4]))
                    i += 7
                default: path.closeSubpath(); i += 1
                }
            }
            return (s, path, color(s.color))
        }
        if cache.count > 32 { cache.removeAll() }
        let b = Built(strokes: strokes, labels: d.labels)
        cache[key] = b
        return b
    }

    static func color(_ hex: String) -> CGColor {
        let rgb = ColorMath.parseHex(hex) ?? 0
        return CGColor(
            srgbRed: CGFloat(rgb >> 16 & 0xff) / 255, green: CGFloat(rgb >> 8 & 0xff) / 255, blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
    }

    /// Draws `spec` into `area`, a rectangle in pt of the context's space.
    static func draw(_ spec: RasterGrid.Spec, in area: CGRect, mirrored: Bool, _ ctx: CGContext) {
        let pt = 72 / 25.4
        let b = built(spec, width: area.width / pt, height: area.height / pt, mirrored: mirrored)
        ctx.saveGState()
        ctx.translateBy(x: area.minX, y: area.minY)
        ctx.scaleBy(x: pt, y: pt)
        let clip = CGRect(x: 0, y: 0, width: area.width / pt, height: area.height / pt)
        for (s, path, color) in b.strokes {
            ctx.saveGState()
            if s.clipped { ctx.clip(to: clip) }
            ctx.addPath(path)
            if s.filled {
                ctx.setFillColor(color)
                ctx.fillPath()
            } else {
                ctx.setStrokeColor(color)
                ctx.setLineWidth(s.weight)
                switch s.style {
                case .dashed: ctx.setLineDash(phase: 0, lengths: [max(1, s.weight * 4), max(0.8, s.weight * 3)])
                case .dotted: ctx.setLineDash(phase: 0, lengths: [max(0.1, s.weight * 0.6), max(0.6, s.weight * 2)])
                case .solid: ctx.setLineDash(phase: 0, lengths: [])
                }
                ctx.strokePath()
            }
            ctx.restoreGState()
        }
        for l in b.labels {
            let size = l.size / pt
            let font = NSFont(name: spec.headerFont?.name ?? "", size: size) ?? .systemFont(ofSize: size)
            let text = NSAttributedString(string: l.text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color(l.color)) ?? .black])
            let line = CTLineCreateWithAttributedString(text)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            let x = switch l.anchor {
            case .start: l.x
            case .middle: l.x - width / 2
            case .end: l.x - width
            }
            ctx.saveGState()
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(x: x, y: l.y)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }
}
