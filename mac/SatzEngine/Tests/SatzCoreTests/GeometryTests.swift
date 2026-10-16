import CoreGraphics
import Testing

@testable import SatzCore

struct GeometryTests {
    let a4 = Sheet(id: "a", x: 0, width: 595, height: 842, bleed: 9)

    @Test func fitCentresTheSpreadWithItsBleed() {
        let v = Viewport.fit([a4], in: CGSize(width: 1000, height: 1000))
        let top = v.toCanvas(CGPoint(x: 0, y: -9))
        let bottom = v.toCanvas(CGPoint(x: 0, y: 851))
        #expect(abs(top.y - (1000 - bottom.y)) < 1e-6)
        #expect(abs(bottom.y - top.y - (1000 - 2 * 64)) < 1e-6)
        let mid = v.toCanvas(CGPoint(x: 297.5, y: 421))
        #expect(abs(mid.x - 500) < 1e-6 && abs(mid.y - 500) < 1e-6)
    }

    @Test func aSpreadFitsAroundItsSpine() {
        let left = Sheet(id: "l", x: -595, width: 595, height: 842, bleed: 9)
        let v = Viewport.fit([left, a4], in: CGSize(width: 1200, height: 800))
        #expect(abs(v.toCanvas(.zero).x - 600) < 1e-6)
    }

    @Test func zoomingKeepsThePointUnderThePointer() {
        let v = Viewport(x: 30, y: -20, zoom: 0.8)
        let p = CGPoint(x: 410, y: 222)
        let spread = v.toSpread(p)
        let w = v.zoomed(to: 3.2, around: p)
        let back = w.toCanvas(spread)
        #expect(abs(back.x - p.x) < 1e-9 && abs(back.y - p.y) < 1e-9)
        #expect(v.zoomed(to: 1e9, around: p).zoom == Viewport.maxZoom)
        #expect(v.zoomed(to: 0, around: p).zoom == Viewport.minZoom)
    }

    @Test func columnsSpanTheirShareOfTheLiveArea() {
        var s = a4
        s.x = 100
        s.grids = [Grid(kind: .columns, count: 2, gutter: 15, margin: 40, size: 0), Grid(kind: .grid, count: 0, gutter: 0, margin: 0, size: 300)]
        let (x, y) = s.gridSpans()
        #expect(x.count == 2 + 1)
        #expect(x[0] == GridSpan(from: 140, to: 140 + 250, margin: 40))
        #expect(x[1].from == 140 + 250 + 15 && x[1].to == 100 + 595 - 40)
        #expect(x[2] == GridSpan(from: 400, to: 400, margin: 0))
        #expect(y.map(\.from) == [300, 600])
    }
}
