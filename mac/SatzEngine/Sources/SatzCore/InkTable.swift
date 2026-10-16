import CoreGraphics
import Foundation
import simd

/// The screen colours of CMYK in the document's print condition, on a grid of `size`
/// steps per ink, which turn the plates of a CMYK page into what it looks like printed;
/// see `INKS` in `web/src/renderer.ts`.
public final class InkTable: Sendable {
    public let size: Int
    /// R, G and B in 0...1 of each grid point, C fastest, then M, Y and K.
    private let rgb: [Float]
    /// Tells tables of different profiles apart.
    public let id: Int

    /// The table of `Engine.lut` pixels: C across and Y down within a tile, M across and
    /// K down between tiles, RGBA.
    public init?(pixels: Data, id: Int) {
        let side = Int(Double(pixels.count / 4).squareRoot().rounded())
        let n = Int(Double(side).squareRoot().rounded())
        guard n >= 2, n * n == side, side * side * 4 == pixels.count else { return nil }
        var rgb = [Float](repeating: 0, count: n * n * n * n * 3)
        pixels.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            for k in 0..<n {
                for y in 0..<n {
                    for m in 0..<n {
                        for c in 0..<n {
                            let px = ((y + n * k) * side + (c + n * m)) * 4
                            let at = (((k * n + y) * n + m) * n + c) * 3
                            for ch in 0..<3 { rgb[at + ch] = Float(p[px + ch]) / 255 }
                        }
                    }
                }
            }
        }
        self.size = n
        self.rgb = rgb
        self.id = id
    }

    /// The screen colour of `cmyk` in 0...1, interpolated between the grid points.
    public func color(_ cmyk: SIMD4<Float>) -> SIMD3<Float> {
        let n = size
        let q = simd_clamp(cmyk, .zero, SIMD4(repeating: 1)) * Float(n - 1)
        let i = SIMD4<Int>(min(Int(q.x), n - 2), min(Int(q.y), n - 2), min(Int(q.z), n - 2), min(Int(q.w), n - 2))
        let f = q - SIMD4<Float>(Float(i.x), Float(i.y), Float(i.z), Float(i.w))
        var out = SIMD3<Float>.zero
        rgb.withUnsafeBufferPointer { t in
            for dk in 0...1 {
                let wk = dk == 0 ? 1 - f.w : f.w
                for dy in 0...1 {
                    let wy = dy == 0 ? 1 - f.z : f.z
                    for dm in 0...1 {
                        let wm = dm == 0 ? 1 - f.y : f.y
                        let base = ((((i.w + dk) * n + i.z + dy) * n + i.y + dm) * n + i.x) * 3
                        let w = wk * wy * wm
                        let a = SIMD3(t[base], t[base + 1], t[base + 2])
                        let b = SIMD3(t[base + 3], t[base + 4], t[base + 5])
                        out += (a * (1 - f.x) + b * f.x) * w
                    }
                }
            }
        }
        return out
    }

    /// The page as it prints from its inverted C, M and Y plate `cmy` and its K plate `k`,
    /// both of one size; `on` keeps or drops C, M, Y and K.
    public func combine(cmy: CGImage, k: CGImage, on: SIMD4<Float> = SIMD4(repeating: 1)) -> CGImage? {
        let w = cmy.width
        let h = cmy.height
        guard k.width == w, k.height == h,
            let a = Self.rgba(cmy), let b = Self.rgba(k),
            let out = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: Painter.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let dst = out.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }
        a.withUnsafeBufferPointer { a in
            b.withUnsafeBufferPointer { b in
                for p in stride(from: 0, to: w * h * 4, by: 4) {
                    let alpha = Float(a[p + 3])
                    guard alpha > 0 else {
                        dst[p] = 0; dst[p + 1] = 0; dst[p + 2] = 0; dst[p + 3] = 0
                        continue
                    }
                    let inks = SIMD4<Float>(
                        1 - Float(a[p]) / alpha, 1 - Float(a[p + 1]) / alpha, 1 - Float(a[p + 2]) / alpha,
                        1 - Float(b[p]) / alpha) * on
                    let s = color(inks) * (alpha / 255)
                    dst[p] = UInt8(min(255, max(0, s.x * 255 + 0.5)))
                    dst[p + 1] = UInt8(min(255, max(0, s.y * 255 + 0.5)))
                    dst[p + 2] = UInt8(min(255, max(0, s.z * 255 + 0.5)))
                    dst[p + 3] = a[p + 3]
                }
            }
        }
        return out.makeImage()
    }

    /// The premultiplied RGBA bytes of `image`.
    static func rgba(_ image: CGImage) -> [UInt8]? {
        let (w, h) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { p -> Bool in
            guard let ctx = CGContext(
                data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: Painter.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.setBlendMode(.copy)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? bytes : nil
    }
}
