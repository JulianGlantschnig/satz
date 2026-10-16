import CoreGraphics
import Foundation

/// Bitmaps of display lists.
public enum Raster {
    /// A premultiplied sRGB bitmap context of `width` × `height` px whose user space is
    /// the page space of `rect` at `scale` px per pt, y down.
    public static func context(rect: CGRect, scale: CGFloat, width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0,
            let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: Painter.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setAllowsFontSubpixelQuantization(false)
        ctx.setShouldSmoothFonts(false)
        return ctx
    }

    /// `ops` over the page space `rect` at `scale` px per pt, on `paper` when given.
    public static func image(
        _ ops: [DisplayList.Op], rect: CGRect, scale: CGFloat, painter: Painter, paper: CGColor? = nil
    ) -> CGImage? {
        let w = Int((rect.width * scale).rounded(.up))
        let h = Int((rect.height * scale).rounded(.up))
        guard let ctx = context(rect: rect, scale: scale, width: w, height: h) else { return nil }
        if let paper {
            ctx.setFillColor(paper)
            ctx.fill(rect)
        }
        painter.draw(ops, in: ctx)
        return ctx.makeImage()
    }
}
