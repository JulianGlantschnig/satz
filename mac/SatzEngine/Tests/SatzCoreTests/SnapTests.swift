import CoreGraphics
import Testing

@testable import SatzCore

private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Box { Box(x: x, y: y, w: w, h: h) }

struct SnapTests {
    let sheet = Sheet(id: "p", x: 0, width: 100, height: 200, bleed: 3)

    @Test func pagesAndLayersGiveTheirEdgesAndCentres() {
        let l = Snap.targets([sheet], [SnapTarget(box: box(10, 20, 30, 40))])
        #expect(l.x.map(\.at) == [0, 50, 100, 10, 25, 40])
        #expect(l.y.map(\.at) == [0, 100, 200, 20, 40, 60])
        #expect(l.x[3] == SnapLine(at: 10, from: 20, to: 60))
    }

    @Test func theNearestValueSnapsWithinTheTolerance() {
        let lines = [SnapLine(at: 10, from: 0, to: 1), SnapLine(at: 50, from: 0, to: 1)]
        #expect(Snap.snap([13, 52], lines, tolerance: 5) == -2)
        #expect(Snap.snap([14], lines, tolerance: 5) == -4)
        #expect(Snap.snap([16, 44], lines, tolerance: 5) == 0)
        #expect(Snap.snap([10], lines, tolerance: 5) == 0)
    }

    @Test func guidesRunThroughTheValuesOnALine() {
        let lines = Snap.targets([sheet], [SnapTarget(box: box(10, 150, 30, 20))])
        #expect(Snap.guides(box(10, 20, 20, 10), lines, xs: [10, 20, 30], ys: [25]) == [SnapGuide(axis: .x, at: 10, from: 20, to: 170)])
        #expect(Snap.guides(box(60, 90, 20, 20), lines, xs: [60, 70, 80], ys: [90, 100, 110]) == [SnapGuide(axis: .y, at: 100, from: 0, to: 100)])
    }

    @Test func theTwoNearestLayersApartAreMeasured() {
        let a = box(0, 0, 10, 10)
        let far = box(100, 0, 10, 10), near = box(20, 0, 10, 10), below = box(0, 30, 10, 10), over = box(5, 5, 10, 10)
        #expect(Snap.nearest(a, [far, over, below, near]) == [near, below])
    }

    @Test func distancesRunAcrossTheGap() {
        #expect(Snap.measure(box(0, 0, 10, 10), box(30, 5, 10, 10)) == [Measure(x1: 10, y1: 7.5, x2: 30, y2: 7.5, length: 20)])
        #expect(Snap.measure(box(0, 0, 10, 10), box(30, 40, 10, 10)) == [
            Measure(x1: 10, y1: 5, x2: 30, y2: 5, length: 20),
            Measure(x1: 30, y1: 5, x2: 30, y2: 40, length: 35, dashed: true),
            Measure(x1: 5, y1: 10, x2: 5, y2: 40, length: 30),
            Measure(x1: 5, y1: 40, x2: 30, y2: 40, length: 25, dashed: true),
        ])
    }

    @Test func aBoxInsideIsMeasuredToTheNearestBesideIt() {
        let page = box(0, 0, 100, 200)
        let others = [box(50, 50, 20, 20), box(80, 20, 10, 10), box(20, 100, 5, 5)]
        #expect(Snap.measure(box(10, 20, 30, 40), page) == [
            Measure(x1: 0, y1: 40, x2: 10, y2: 40, length: 10), Measure(x1: 40, y1: 40, x2: 100, y2: 40, length: 60),
            Measure(x1: 25, y1: 0, x2: 25, y2: 20, length: 20), Measure(x1: 25, y1: 60, x2: 25, y2: 200, length: 140),
        ])
        #expect(Snap.measure(box(10, 20, 30, 40), page, others: others) == [
            Measure(x1: 0, y1: 40, x2: 10, y2: 40, length: 10), Measure(x1: 40, y1: 55, x2: 50, y2: 55, length: 10),
            Measure(x1: 25, y1: 0, x2: 25, y2: 20, length: 20), Measure(x1: 22.5, y1: 60, x2: 22.5, y2: 100, length: 40),
        ])
    }

    @Test func aBoxSnapsToTheGapOfItsColumn() {
        let others = [box(0, 0, 20, 10), box(0, 20, 20, 10), box(0, 60, 20, 10)]
        #expect(Snap.spacings(box(0, 38, 20, 10), others, axis: .y) == [40, 40, 40])
        let eq = Snap.equals(box(0, 40, 20, 10), others, axis: .y).map { [$0.y1, $0.y2] }.sorted { $0[0] < $1[0] }
        #expect(eq == [[10, 20], [30, 40], [50, 60]])
        #expect(Snap.equals(box(0, 42, 20, 10), others, axis: .y).isEmpty)
    }
}

struct HandleTests {
    let view = Viewport(x: 100, y: 50, zoom: 2)
    let b = Box(x: -20, y: 10, w: 50, h: 40)

    @Test func cornersWinOverEdges() {
        func at(_ x: Double, _ y: Double) -> Handle? { Handles.at(view, CGPoint(x: x, y: y), box: b) }
        #expect(at(60, 70) == .resize("nw"))
        #expect(at(163, 147) == .resize("se"))
        #expect(at(110, 67) == .resize("n"))
        #expect(at(57, 100) == .resize("w"))
        #expect(at(163, 100) == .resize("e"))
        #expect(at(110, 100) == nil)
        #expect(at(50, 60) == .rotate("nw"))
        #expect(at(170, 160) == .rotate("se"))
        #expect(at(50, 100) == nil)
    }

    @Test func radiusHandlesAndFlatBoxes() {
        let radii = Handles.radiusHandles(view, b, radii: [0, 0, 0, 0])
        #expect(Handles.at(view, CGPoint(x: 79, y: 82), box: b, radii: radii) == .radius(0))
        #expect(Handles.at(view, CGPoint(x: 60, y: 70), box: b, radii: radii) == .resize("nw"))
        var flat = b
        flat.h = 0
        #expect(Handles.at(view, CGPoint(x: 60, y: 70), box: flat) == .resize("w"))
    }

    @Test func lineEnds() {
        let line = (CGPoint(x: -10, y: 0), CGPoint(x: 10, y: 0))
        #expect(Handles.at(view, CGPoint(x: 84, y: 50), line: line) == .end(0))
        #expect(Handles.at(view, CGPoint(x: 124, y: 53), line: line) == .end(1))
        #expect(Handles.at(view, CGPoint(x: 100, y: 50), line: line) == nil)
        #expect(Handles.at(view, CGPoint(x: 70, y: 50), line: line) == .rotate("nw"))
        #expect(Handles.at(view, CGPoint(x: 130, y: 55), line: line) == .rotate("se"))
        #expect(Handles.at(view, CGPoint(x: 90, y: 50), line: line) == nil)
    }

    @Test func ports() {
        let p = Handles.ports(view, b)
        #expect(p.in == CGPoint(x: 60, y: 86) && p.out == CGPoint(x: 160, y: 134))
        #expect(Handles.port((p.in, p.out), at: CGPoint(x: 165, y: 130)) == .out)
        #expect(Handles.port((p.in, p.out), at: CGPoint(x: 110, y: 110)) == nil)
    }

    @Test func resizingScalesTheFrames() {
        let left = Box(x: -20, y: 10, w: 10, h: 10), right = Box(x: 20, y: 40, w: 10, h: 10)
        #expect(Handles.resized(b, handle: "e", by: CGPoint(x: 50, y: 0), alt: false, shift: false, frames: [left, right])
            == [Box(x: -20, y: 10, w: 20, h: 10), Box(x: 60, y: 40, w: 20, h: 10)])
        #expect(Handles.resized(b, handle: "w", by: CGPoint(x: 60, y: 0), alt: false, shift: false, frames: [left]) == [Box(x: 38, y: 10, w: 2, h: 10)])
        #expect(Handles.resized(b, handle: "e", by: CGPoint(x: 10, y: 0), alt: true, shift: false, frames: [b]) == [Box(x: -30, y: 10, w: 70, h: 40)])
        #expect(Handles.resized(b, handle: "se", by: CGPoint(x: 50, y: 0), alt: false, shift: true, frames: [b]) == [Box(x: -20, y: 10, w: 100, h: 80)])
        #expect(Handles.resized(b, handle: "s", by: CGPoint(x: 0, y: 40), alt: false, shift: true, frames: [b]) == [Box(x: -45, y: 10, w: 100, h: 80)])
        #expect(Handles.resized(b, handle: "s", by: CGPoint(x: 0, y: -20), alt: false, shift: true, frames: [b]) == [Box(x: -7.5, y: 10, w: 25, h: 20)])
        #expect(Handles.resized(b, handle: "w", by: CGPoint(x: 25, y: 0), alt: false, shift: true, frames: [b]) == [Box(x: 5, y: 20, w: 25, h: 20)])
    }
}

@MainActor
struct SelectTests {
    /// page: frame f [ group g [ a, b ] ], group h [ group i [ c ] ], built in an engine.
    func tree() throws -> (nodes: [Node], ids: [String: String]) {
        let e = Engine.blank(width: 500, height: 500, pages: 1, facing: false)
        let page = try e.snapshot.pages[0].id
        func make(_ kind: NewKind, _ parent: String) throws -> String {
            try e.apply(.create(parent: parent, kind: kind, x: 10, y: 10, w: 50, h: 50))[0]
        }
        let f = try make(.frame, page)
        let a = try make(.rect, f), b = try make(.rect, f)
        let g = try e.apply(.group([a, b], frame: false))[0]
        let c = try make(.rect, page)
        let i = try e.apply(.group([c], frame: false))[0]
        let h = try e.apply(.group([i], frame: false))[0]
        return (try e.snapshot.pages[0].children, ["f": f, "g": g, "a": a, "b": b, "h": h, "i": i, "c": c])
    }

    @Test func clicksPickByDepth() throws {
        let (nodes, id) = try tree()
        func pick(_ path: [String], _ sel: [String], _ mode: Select.Mode) -> String? {
            Select.pick(nodes, path: path.map { id[$0]! }, selection: sel.map { id[$0]! }, mode: mode)
        }
        #expect(pick(["f", "g", "a"], [], .click) == id["g"])
        #expect(pick(["h", "i", "c"], [], .click) == id["h"])
        #expect(pick(["f"], [], .click) == id["f"])
        #expect(pick([], ["a"], .click) == nil)
        #expect(pick(["f", "g", "b"], ["a"], .click) == id["b"])
        #expect(pick(["h", "i", "c"], ["a"], .click) == id["h"])
        #expect(pick(["h", "i", "c"], ["h"], .double) == id["i"])
        #expect(pick(["h", "i", "c"], ["i"], .double) == id["c"])
        #expect(pick(["h", "i", "c"], [], .double) == id["h"])
        #expect(pick(["h", "i", "c"], [], .deep) == id["c"])
    }

    @Test func shiftClickSpans() {
        let list = ["0", "1", "2", "3", "4", "5", "6"]
        func span(_ s: [String], _ id: String) -> [String]? { Select.span(list, selection: s, id: id)?.sorted() }
        #expect(span(["1", "2", "3", "4"], "6") == ["1", "2", "3", "4", "5", "6"])
        #expect(span(["1", "2", "3", "4", "5", "6"], "2") == ["1", "2"])
        #expect(span(["1", "2"], "0") == ["0", "1", "2"])
        #expect(span(["1", "2", "3", "4"], "2") == ["1", "2"])
        #expect(span(["x", "1", "3"], "5") == ["1", "3", "4", "5", "x"])
        #expect(Select.span(list, selection: ["3"], id: "5")?.last == "5")
        #expect(Select.span(list, selection: ["x"], id: "5") == nil)
    }
}
