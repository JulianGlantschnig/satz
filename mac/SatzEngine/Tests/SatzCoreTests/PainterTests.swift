import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SatzCore

/// RGBA pixels of `image`, premultiplied onto white.
func pixels(_ image: CGImage) -> [UInt8] {
    let ctx = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: Painter.srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(.white)
    ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
}

/// The mean difference per channel of two images of one size, 0...255, and the share of
/// pixels whose difference is beyond `far`.
func difference(_ a: CGImage, _ b: CGImage, far: Int = 64) -> (mean: Double, beyond: Double) {
    let (p, q) = (pixels(a), pixels(b))
    var sum = 0
    var count = 0
    for i in stride(from: 0, to: p.count, by: 4) {
        var worst = 0
        for c in 0..<3 {
            let d = abs(Int(p[i + c]) - Int(q[i + c]))
            sum += d
            worst = max(worst, d)
        }
        if worst > far { count += 1 }
    }
    return (Double(sum) / Double(p.count / 4 * 3), Double(count) / Double(p.count / 4))
}

func write(_ image: CGImage, to path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

@MainActor
struct PainterTests {
    /// Renders every page of `name` as the canvas does and as the engine rasterizes it for print.
    func compare(_ name: String, ppi: Float = 72) async throws -> [(page: Int, mean: Double, beyond: Double)] {
        let engine = try Engine.load(example(name))
        let resources = Resources()
        let painter = Painter(resources: resources)
        let snap = try engine.snapshot
        var out: [(Int, Double, Double)] = []
        for (i, page) in snap.pages.enumerated() {
            let ops = try DisplayList.decode(engine.displayList(page: page.id))
            resources.prepare(ops)
            while resources.decoding { try await Task.sleep(for: .milliseconds(20)) }
            let scale = CGFloat(ppi / 72)
            let rect = CGRect(x: 0, y: 0, width: page.width, height: page.height)
            let ours: CGImage
            if snap.colorMode == .cmyk {
                // CMYK pages show as their plates print, on the profile's paper.
                let table = try #require(InkTable(pixels: engine.lut(), id: 1))
                let cmy = try DisplayList.decode(engine.plate(page: page.id, k: false))
                let k = try DisplayList.decode(engine.plate(page: page.id, k: true))
                resources.prepare(cmy + k)
                while resources.decoding { try await Task.sleep(for: .milliseconds(20)) }
                let a = try #require(Raster.image(cmy, rect: rect, scale: scale, painter: painter, paper: .white))
                let b = try #require(Raster.image(k, rect: rect, scale: scale, painter: painter, paper: .white))
                ours = try #require(table.combine(cmy: a, k: b))
            } else {
                ours = try #require(Raster.image(ops, rect: rect, scale: scale, painter: painter, paper: .white))
            }
            let png = try #require(engine.png(page: page.id, ppi: ppi))
            let theirs = try #require(Resources.cgImage(png))
            #expect(ours.width == theirs.width && ours.height == theirs.height, "page \(i + 1) size")
            guard ours.width == theirs.width, ours.height == theirs.height else { continue }
            if let dir = ProcessInfo.processInfo.environment["SATZ_DUMP"] {
                write(ours, to: "\(dir)/\(name)-\(i + 1)-mac.png")
                write(theirs, to: "\(dir)/\(name)-\(i + 1)-engine.png")
            }
            let d = difference(ours, theirs)
            out.append((i + 1, d.mean, d.beyond))
        }
        return out
    }

    // The canvas blends CMYK documents in CMYK, as the web app does, where the engine's
    // PNG blends in RGB; soft shadows and glows over dark inks differ, the rest agrees.
    @Test func theBookletDrawsAsTheEngineRasterizesIt() async throws {
        for (page, mean, beyond) in try await compare("booklet") {
            #expect(mean < 5, "page \(page): mean difference \(mean)")
            #expect(beyond < 0.01, "page \(page): \(beyond * 100)% of pixels differ")
        }
    }

    @Test func thePosterDrawsAsTheEngineRasterizesIt() async throws {
        for (page, mean, beyond) in try await compare("poster", ppi: 36) {
            #expect(mean < 5, "page \(page): mean difference \(mean)")
            #expect(beyond < 0.01, "page \(page): \(beyond * 100)% of pixels differ")
        }
    }

    @Test func pathsReadTheEnginesVerbs() {
        let p = Painter.path([0, 0, 0, 1, 10, 0, 4, 10, 5, 5, 10, 0, 10, 5])
        #expect(p.boundingBoxOfPath.maxX == 10)
        #expect(p.boundingBoxOfPath.maxY == 10)
    }
}

@MainActor @Test func aCanvasTileDrawsQuickly() async throws {
    let engine = try Engine.load(example("poster"))
    let page = try engine.snapshot.pages[0]
    let resources = Resources()
    let painter = Painter(resources: resources)
    let cmy = try DisplayList.decode(engine.plate(page: page.id, k: false))
    let k = try DisplayList.decode(engine.plate(page: page.id, k: true))
    resources.prepare(cmy + k)
    while resources.decoding { try await Task.sleep(for: .milliseconds(20)) }
    let table = try #require(InkTable(pixels: engine.lut(), id: 1))
    // A 512 pt tile at 2x on a Retina screen, at 100 % around the title.
    let rect = CGRect(x: 600, y: 1100, width: 512, height: 512)
    let start = ContinuousClock.now
    let a = try #require(Raster.image(cmy, rect: rect, scale: 2, painter: painter, paper: .white))
    let b = try #require(Raster.image(k, rect: rect, scale: 2, painter: painter, paper: .white))
    let plates = ContinuousClock.now - start
    _ = try #require(table.combine(cmy: a, k: b))
    let all = ContinuousClock.now - start
    print("TILE plates \(plates) total \(all)")
    #expect(all < .seconds(2))
}
