import Testing

@testable import SatzCore

@MainActor
struct ColorMathTests {
    @Test func hsvRoundTrips() {
        for rgb: UInt32 in [0xff0000, 0x00ff00, 0x0000ff, 0x336699, 0xffffff, 0x000000, 0xfa8072] {
            #expect(ColorMath.rgb(ColorMath.hsv(rgb)) == rgb)
        }
        #expect(ColorMath.hsv(0xff0000) == HSV(0, 1, 1))
    }

    @Test func hexReadsShortAndLong() {
        #expect(ColorMath.parseHex("#FA0") == 0xffaa00)
        #expect(ColorMath.parseHex("336699") == 0x336699)
        #expect(ColorMath.parseHex("xyz") == nil)
        #expect(ColorMath.hex(0x0a0b0c) == "0A0B0C")
    }

    @Test func cmykReadsAndWrites() {
        #expect(ColorMath.parseCMYK("20, 40, 0, 10") == [0.2, 0.4, 0, 0.1])
        #expect(ColorMath.parseCMYK("C20 M40 Y0 K10") == [0.2, 0.4, 0, 0.1])
        #expect(ColorMath.parseCMYK("C:20 M:40 Y:0 K:10") == [0.2, 0.4, 0, 0.1])
        #expect(ColorMath.parseCMYK("20% 40% 0% 10%") == [0.2, 0.4, 0, 0.1])
        #expect(ColorMath.parseCMYK("20 40 0") == nil)
        #expect(ColorMath.parseCMYK("M20 C40 Y0 K10") == nil)
        #expect(ColorMath.cmykText([0.2, 0.455, 0, 1]) == "C:20 M:45.5 Y:0 K:100")
    }

    @Test func gradientsTurnAndSplit() {
        #expect(abs(ColorMath.angle(ColorMath.linear(30)) - 30) < 1e-9)
        let p = ColorMath.retype(Fill.solid(.black), .linear)
        #expect(p.stops.count == 2 && p.stops[1].color.alpha == 0)
        let s = ColorMath.split([Fill.Stop(at: 0, color: .black), Fill.Stop(at: 0.2, color: .white), Fill.Stop(at: 1, color: .black)])
        #expect(s.map(\.at) == [0, 0.2, 0.6, 1])
        #expect(ColorMath.retype(p, .solid).color == .black)
    }

    @Test func swatchesResolveThroughTheEngine() throws {
        let e = try Engine.load(example("booklet"))
        let s = try e.snapshot
        let scope = Scope(s)
        let swatch = try #require(s.swatches.first)
        let c = ColorMath.resolve(.swatch(swatch.id, tint: 0.5, alpha: 1), scope)
        guard case .cmyk(let k, _) = c else { Issue.record("not CMYK"); return }
        #expect(abs(k[1] - 0.275) < 1e-6)
        #expect(ColorMath.rgb(.rgb(0xff8000ff), scope) == 0xff8000)
        if case .cmyk = ColorMath.neutral("black", .cmyk) {} else { Issue.record("black is not CMYK") }
    }
}
