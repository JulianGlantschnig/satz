import Foundation
import Testing

@testable import SatzCore

@Suite struct RasterGridTests {
    /// The [x, y] of each move of a display-list path.
    func starts(_ path: [Double]) -> [[Double]] {
        var out: [[Double]] = []
        var i = 0
        while i < path.count {
            switch path[i] {
            case 0: out.append([path[i + 1], path[i + 2]]); i += 3
            case 1: i += 3
            case 4: i += 7
            default: i += 1
            }
        }
        return out
    }

    @Test func linesStepFromTheTopLeftAndEveryNthIsHeavier() {
        var s = RasterGrid.Spec()
        s.hSpacing = 10
        s.vSpacing = 10
        s.emphasize = 5
        s.thickness = 0.2
        let d = RasterGrid.build(s, width: 100, height: 50)
        #expect(d.strokes.count == 2)
        let thin = d.strokes.first { $0.weight == 0.2 }!, heavy = d.strokes.first { $0.weight > 0.2 }!
        #expect(abs(heavy.weight - 0.36) < 1e-9)
        // y = 0 and x = 0 are lines 0, which every 5th is.
        let ys = starts(heavy.path).map { $0[1] }
        #expect(ys.contains(0) && ys.contains(50) && !ys.contains(10))
        #expect(starts(thin.path).contains { $0[1] == 10 })
        #expect(d.strokes.allSatisfy { $0.clipped && !$0.filled && $0.color == "#FF4848" })
    }

    @Test func millimetrePaperHasThreeWeightsAndDotsAreFilled() {
        var s = RasterGrid.Spec()
        s.kind = .mm
        #expect(Set(RasterGrid.build(s, width: 30, height: 30).strokes.map(\.weight)).count == 3)
        s.kind = .dots
        let dots = RasterGrid.build(s, width: 30, height: 30).strokes
        #expect(dots.count == 1 && dots[0].filled && dots[0].weight == 0)
    }

    @Test func axisColoursAndTheSecondaryRasterBelow() {
        var s = RasterGrid.Spec()
        s.axisColors = true
        s.secondary = true
        s.secondaryKind = .lines
        let d = RasterGrid.build(s, width: 40, height: 40)
        #expect(d.strokes.first?.color == s.secondaryColor)
        #expect(d.strokes.first?.weight == s.secondaryThickness)
        #expect(d.strokes.contains { $0.color == s.colorH } && d.strokes.contains { $0.color == s.colorV })
    }

    @Test func holesSitInTheSpineMarginAndMirrorOnLeftPages() throws {
        var s = RasterGrid.Spec()
        s.punch = .four
        s.marginLeft = 20
        s.marginRight = 10
        s.rotation = 30
        let right = RasterGrid.build(s, width: 180, height: 277)
        let holes = right.strokes.filter { !$0.clipped }
        #expect(holes.count == 2 && holes.allSatisfy { $0.color == "#888888" })
        // In the left margin, 8 mm from the paper edge, not turned with the raster.
        let xs = Set(holes.flatMap { starts($0.path) }.map { ($0[0] * 1000).rounded() / 1000 })
        #expect(xs.contains(-12 + 3) && xs.contains(-12 - 1.5))
        let left = RasterGrid.build(s, width: 180, height: 277, mirrored: true)
        let mirrored = try #require(left.strokes.first { !$0.clipped })
        // The right margin of 10 mm is at the spine now: 5 mm into it.
        #expect(starts(mirrored.path).contains { abs($0[0] - (180 + 5 + 3)) < 1e-9 })
    }

    @Test func theHeaderAndItsDateMirrorTheirSides() throws {
        var s = RasterGrid.Spec()
        s.header = true
        s.headerText = "Physik"
        s.headerPosition = .topLeft
        s.headerDate = true
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-18T12:00:00Z"))
        let d = RasterGrid.build(s, width: 100, height: 100, date: date)
        #expect(d.labels.map(\.text) == ["Physik", "2026-10-18"])
        #expect(d.labels[0].x == 3 && d.labels[0].anchor == .start)
        let m = RasterGrid.build(s, width: 100, height: 100, mirrored: true, date: date)
        #expect(m.labels[0].x == 97 && m.labels[0].anchor == .end && m.labels[1].anchor == .start)
    }

    @Test func aSpecKeepsItsSettingsAndOlderOnesTakeDefaults() throws {
        var s = RasterGrid.Spec()
        s.kind = .hex
        s.headerFont = Typeface(name: "Inter", family: "Inter", style: "Regular", hash: "h")
        s.name = "Karte"
        #expect(RasterGrid.Spec.from(json: s.json) == s)
        let old = try #require(RasterGrid.Spec.from(json: #"{"kind":"polar","polarRays":12}"#))
        #expect(old.kind == .polar && old.polarRays == 12 && old.name.isEmpty && old.hexSize == 8)
        for kind in RasterGrid.Kind.allCases {
            var k = RasterGrid.Spec()
            k.kind = kind
            k.curve = .wave
            #expect(!RasterGrid.build(k, width: 50, height: 70).strokes.isEmpty, "\(kind)")
        }
    }
}
