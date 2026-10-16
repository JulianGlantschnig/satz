import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Fonts and images of display lists by their ids, for drawing on any thread.
public protocol PaintResources: Sendable {
    /// The font `id` at `size` pt; ids marked `DisplayList.missingFont` are the bundled one.
    func font(_ id: UInt32, size: CGFloat) -> CTFont?
    /// The decoded image `id`, or nil while it decodes or when it does not.
    func image(_ id: UInt32) -> CGImage?
}

/// Draws display lists with Core Graphics into a context whose user space is the
/// page's: points, y down. Thread-safe as long as its resources are.
public struct Painter: Sendable {
    public let resources: any PaintResources

    public init(resources: any PaintResources) {
        self.resources = resources
    }

    public static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Draws `ops`, skipping a leading `page` op.
    public func draw(_ ops: [DisplayList.Op], in ctx: CGContext) {
        var from = 0
        if case .page = ops.first { from = 1 }
        draw(ops, from, ops.count, ctx)
    }

    private func draw(_ ops: [DisplayList.Op], _ from: Int, _ to: Int, _ ctx: CGContext) {
        var i = from
        while i < to {
            let op = ops[i]
            switch op {
            case .beginItem:
                let end = DisplayList.closing(ops, i)
                draw(ops, i + 1, end, ctx)
                i = end
            case .pushClip(let path, let invert):
                let end = DisplayList.closing(ops, i)
                ctx.saveGState()
                if invert {
                    // Core Graphics has no difference clip: erase the path from a layer.
                    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                    draw(ops, i + 1, end, ctx)
                    ctx.setBlendMode(.destinationOut)
                    ctx.addPath(Self.path(path))
                    ctx.setFillColor(gray: 0, alpha: 1)
                    ctx.fillPath()
                    ctx.endTransparencyLayer()
                } else {
                    ctx.addPath(Self.path(path))
                    ctx.clip()
                    draw(ops, i + 1, end, ctx)
                }
                ctx.restoreGState()
                i = end
            case .pushTransform(let t):
                let end = DisplayList.closing(ops, i)
                ctx.saveGState()
                ctx.concatenate(Self.transform(t))
                draw(ops, i + 1, end, ctx)
                ctx.restoreGState()
                i = end
            case .pushLayer(_, let opacity, let blend, let blur, let shadows):
                let end = DisplayList.closing(ops, i)
                ctx.saveGState()
                ctx.setAlpha(CGFloat(opacity))
                ctx.setBlendMode(Self.blend(blend))
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                ctx.setAlpha(1)
                ctx.setBlendMode(.normal)
                if blur > 0 || !shadows.isEmpty {
                    drawFiltered(ctx, blur: blur, shadows: shadows) { draw(ops, i + 1, end, $0) }
                } else {
                    draw(ops, i + 1, end, ctx)
                }
                ctx.endTransparencyLayer()
                ctx.restoreGState()
                i = end
            case .beginMask:
                let mid = DisplayList.closing(ops, i)
                let end = DisplayList.closing(ops, mid)
                ctx.saveGState()
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                draw(ops, mid + 1, end, ctx)
                ctx.setBlendMode(.destinationIn)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                ctx.setBlendMode(.normal)
                draw(ops, i + 1, mid, ctx)
                ctx.endTransparencyLayer()
                ctx.endTransparencyLayer()
                ctx.restoreGState()
                i = end
            case .fillPath(let paint, let path):
                ctx.addPath(Self.path(path))
                fill(paint, ctx)
            case .strokePath(let paint, let width, let cap, let join, let path):
                ctx.saveGState()
                ctx.setLineWidth(CGFloat(width))
                ctx.setLineCap([.butt, .round, .square][Int(min(cap, 2))])
                ctx.setLineJoin([.miter, .round, .bevel][Int(min(join, 2))])
                ctx.setMiterLimit(4)
                ctx.addPath(Self.path(path))
                ctx.replacePathWithStrokedPath()
                fill(paint, ctx)
                ctx.restoreGState()
            case .glyphRun(let font, let size, let paint, let glyphs, let positions):
                drawGlyphs(font: font, size: size, paint: paint, glyphs: glyphs, positions: positions, ctx)
            case .image(let id, let t):
                guard let image = resources.image(id) else { break }
                ctx.saveGState()
                ctx.concatenate(Self.transform(t))
                // Images draw upright in y-up space; the unit square is y down.
                ctx.translateBy(x: 0, y: 1)
                ctx.scaleBy(x: 1, y: -1)
                ctx.interpolationQuality = .high
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                ctx.restoreGState()
            case .page, .endItem, .popClip, .popLayer, .endMask, .popMask, .popTransform:
                break
            }
            i += 1
        }
    }

    /// Fills the context's path with `paint`, nonzero, and clears the path.
    private func fill(_ paint: DisplayList.Paint, _ ctx: CGContext) {
        switch paint {
        case .solid(let c):
            ctx.setFillColor(Self.color(c))
            ctx.fillPath()
        case .linear(let t, let stops), .radial(let t, let stops):
            guard stops.count >= 2, let gradient = Self.gradient(stops) else {
                ctx.setFillColor(Self.color(stops.first?.color ?? [0, 0, 0, 0]))
                ctx.fillPath()
                return
            }
            ctx.saveGState()
            ctx.clip()
            drawGradient(gradient, linear: { if case .linear = paint { true } else { false } }(), t, ctx)
            ctx.restoreGState()
        }
    }

    private func drawGradient(_ gradient: CGGradient, linear: Bool, _ t: [Float], _ ctx: CGContext) {
        let m = Self.transform(t)
        // A gradient squashed to a line paints nothing, as Skia's does.
        guard abs(m.a * m.d - m.b * m.c) > 1e-12 else { return }
        ctx.concatenate(m)
        let extend: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        if linear {
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1, y: 0), options: extend)
        } else {
            ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: extend)
        }
    }

    private func drawGlyphs(
        font id: UInt32, size: Float, paint: DisplayList.Paint, glyphs: [UInt16], positions: [Float], _ ctx: CGContext
    ) {
        guard !glyphs.isEmpty, let font = resources.font(id, size: CGFloat(size)) else { return }
        let points = (0..<glyphs.count).map { CGPoint(x: CGFloat(positions[2 * $0]), y: CGFloat(positions[2 * $0 + 1])) }
        // Positions are in text space, which the flipped text matrix turns upside down too.
        let flipped = points.map { CGPoint(x: $0.x, y: -$0.y) }
        if id & DisplayList.missingFont != 0 {
            // Marks text whose font is missing, as the web canvas does.
            var advances = [CGSize](repeating: .zero, count: glyphs.count)
            CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
            let x0 = points[0].x
            let x1 = points[points.count - 1].x + advances[advances.count - 1].width
            let y = points[0].y
            ctx.setFillColor(CGColor(srgbRed: 1, green: 64 / 255, blue: 160 / 255, alpha: 0.6))
            ctx.fill(CGRect(x: x0, y: y - CTFontGetAscent(font), width: x1 - x0, height: CTFontGetAscent(font) + CTFontGetDescent(font)))
        }
        ctx.saveGState()
        // Glyphs stand upright in y-up text space; the page is y down.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        switch paint {
        case .solid(let c):
            ctx.setFillColor(Self.color(c))
            ctx.setTextDrawingMode(.fill)
            CTFontDrawGlyphs(font, glyphs, flipped, glyphs.count, ctx)
        case .linear(let t, let stops), .radial(let t, let stops):
            if stops.count >= 2, let gradient = Self.gradient(stops) {
                ctx.setTextDrawingMode(.clip)
                CTFontDrawGlyphs(font, glyphs, flipped, glyphs.count, ctx)
                drawGradient(gradient, linear: { if case .linear = paint { true } else { false } }(), t, ctx)
            } else {
                ctx.setFillColor(Self.color(stops.first?.color ?? [0, 0, 0, 0]))
                ctx.setTextDrawingMode(.fill)
                CTFontDrawGlyphs(font, glyphs, flipped, glyphs.count, ctx)
            }
        }
        ctx.restoreGState()
    }

    // MARK: Blur and shadows

    /// Core Image renders on any thread.
    static let ciContext = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb])

    /// Core Image's Gaussian blur radius for a sigma of 1.
    static let ciRadiusPerSigma: CGFloat = 1

    /// Draws what `body` draws blurred by `blur` and under `shadows`, through a bitmap in
    /// device space over the context's clip, grown by how far the blurs reach.
    private func drawFiltered(
        _ ctx: CGContext, blur: Float, shadows: [DisplayList.Shadow], body: (CGContext) -> Void
    ) {
        let toDevice = ctx.userSpaceToDeviceSpaceTransform
        let scale = sqrt(abs(toDevice.a * toDevice.d - toDevice.b * toDevice.c))
        let reach = 3 * CGFloat(([blur] + shadows.map(\.blur)).max() ?? 0) * scale
            + (shadows.map { hypot(CGFloat($0.offset[0]), CGFloat($0.offset[1])) }.max() ?? 0) * scale
        let clip = ctx.boundingBoxOfClipPath.applying(toDevice).insetBy(dx: -reach, dy: -reach).integral
        // A layer far larger than any screen is cut to a sane size; it only blurs less at its edges.
        let area = clip.intersection(CGRect(x: clip.midX - 8192, y: clip.midY - 8192, width: 16384, height: 16384))
        guard area.width >= 1, area.height >= 1,
            let off = CGContext(
                data: nil, width: Int(area.width), height: Int(area.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: Self.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        // The bitmap's device space is the context's, moved to the area's corner.
        off.translateBy(x: -area.minX, y: -area.minY)
        off.concatenate(toDevice)
        body(off)
        guard let content = off.makeImage() else { return }
        let ci = CIImage(cgImage: content)
        let context = Self.ciContext

        func blurred(_ image: CIImage, sigma: CGFloat) -> CIImage {
            guard sigma > 0 else { return image }
            return image.clampedToExtent()
                .applyingGaussianBlur(sigma: Double(sigma * Self.ciRadiusPerSigma))
                .cropped(to: image.extent)
        }

        ctx.saveGState()
        // Draw in device space, where the bitmap sits at `area`.
        ctx.concatenate(toDevice.inverted())
        for s in shadows {
            let c = s.color
            // The shadow is the content's alpha in the shadow's colour, blurred and moved.
            let tint = CIImage(color: CIColor(red: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: CGFloat(c[3]), colorSpace: Self.srgb)!)
                .cropped(to: ci.extent)
            let shape = tint.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: ci])
            let offset = CGSize(width: CGFloat(s.offset[0]), height: CGFloat(s.offset[1])).applying(toDevice)
            let shadow = blurred(
                shape.transformed(by: CGAffineTransform(translationX: offset.width, y: offset.height)).cropped(to: ci.extent.union(ci.extent.offsetBy(dx: offset.width, dy: offset.height))),
                sigma: CGFloat(s.blur) * scale)
            if let image = context.createCGImage(shadow, from: shadow.extent) {
                ctx.draw(image, in: shadow.extent.offsetBy(dx: area.minX, dy: area.minY))
            }
        }
        let top = blurred(ci, sigma: CGFloat(blur) * scale)
        if let image = blur > 0 ? context.createCGImage(top, from: top.extent) : content {
            ctx.draw(image, in: area)
        }
        ctx.restoreGState()
    }

    // MARK: Conversions

    public static func color(_ c: [Float]) -> CGColor {
        CGColor(srgbRed: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: CGFloat(c[3]))
    }

    static func gradient(_ stops: [DisplayList.Stop]) -> CGGradient? {
        CGGradient(
            colorsSpace: srgb, colors: stops.map { color($0.color) } as CFArray,
            locations: stops.map { CGFloat($0.at) })
    }

    /// [a b c d e f] as an affine transform.
    public static func transform(_ t: [Float]) -> CGAffineTransform {
        CGAffineTransform(a: CGFloat(t[0]), b: CGFloat(t[1]), c: CGFloat(t[2]), d: CGFloat(t[3]), tx: CGFloat(t[4]), ty: CGFloat(t[5]))
    }

    public static func path(_ p: [Float]) -> CGPath {
        let path = CGMutablePath()
        var i = 0
        func pt(_ k: Int) -> CGPoint { CGPoint(x: CGFloat(p[k]), y: CGFloat(p[k + 1])) }
        while i < p.count {
            switch p[i] {
            case DisplayList.move:
                guard i + 2 < p.count else { return path }
                path.move(to: pt(i + 1))
                i += 3
            case DisplayList.line:
                guard i + 2 < p.count else { return path }
                if path.isEmpty { path.move(to: pt(i + 1)) } else { path.addLine(to: pt(i + 1)) }
                i += 3
            case DisplayList.cubic:
                guard i + 6 < p.count else { return path }
                if path.isEmpty { path.move(to: pt(i + 5)) }
                path.addCurve(to: pt(i + 5), control1: pt(i + 1), control2: pt(i + 3))
                i += 7
            case DisplayList.close:
                if !path.isEmpty { path.closeSubpath() }
                i += 1
            default:
                return path
            }
        }
        return path
    }

    private static let blends: [CGBlendMode] = [
        .normal, .multiply, .screen, .overlay, .darken, .lighten, .colorDodge, .colorBurn,
        .hardLight, .softLight, .difference, .exclusion, .hue, .saturation, .color, .luminosity,
    ]

    static func blend(_ i: UInt32) -> CGBlendMode { blends.indices.contains(Int(i)) ? blends[Int(i)] : .normal }
}
