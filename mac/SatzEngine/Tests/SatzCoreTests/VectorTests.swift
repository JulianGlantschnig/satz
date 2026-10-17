import Foundation
import Testing

@testable import SatzCore

/// See `web/src/vector.test.ts` and `web/src/pen.test.ts`.
struct VectorTests {
    let MOVE = 0.0, LINE = 1.0, CUBIC = 4.0, CLOSE = 5.0
    var square: [Double] { [MOVE, 0, 0, LINE, 10, 0, LINE, 10, 10, LINE, 0, 10, LINE, 0, 0, CLOSE] }
    var arc: [Double] { [MOVE, 0, 0, CUBIC, 0, 5, 5, 10, 10, 10] }

    @Test func aPathParsesIntoKnotsAndBackAClosedOneWithoutItsClosingKnot() {
        let cs = Vector.contours(square)
        #expect(cs.count == 1)
        #expect(cs[0].closed)
        #expect(cs[0].knots.map { [$0.x, $0.y] } == [[0, 0], [10, 0], [10, 10], [0, 10]])
        #expect(Vector.path(cs) == square)
        #expect(Vector.path(Vector.contours(arc)) == arc)
    }

    @Test func aKnotSplitsALineWhereItIsNearestAndKeepsItALine() {
        let cs = Vector.contours(square)
        let near = Vector.nearest(cs, CGPoint(x: 5, y: 1))
        #expect(near.at == Vector.At(0, 0))
        #expect(abs(near.t - 0.5) < 1e-9)
        #expect(Array(Vector.path(Vector.split(cs, near.at, near.t)).prefix(9)) == [MOVE, 0, 0, LINE, 5, 0, LINE, 10, 0])
        #expect(Vector.nearest(cs, CGPoint(x: 1, y: 5)).at == Vector.At(0, 3))
    }

    @Test func aKnotSplitsACurveIntoTwoCurvesAlongIt() {
        let c = Vector.split(Vector.contours(arc), Vector.At(0, 0), 0.5)[0]
        #expect(c.knots.count == 3)
        #expect(c.knots[1].x == 3.125 && c.knots[1].y == 6.875)
        #expect(Vector.path([c])[3] == CUBIC)
    }

    @Test func aRemovedKnotJoinsItsNeighboursAndAContourOfOneKnotGoes() {
        #expect(Vector.path(Vector.remove(Vector.contours(square), [Vector.At(0, 1)])) == [MOVE, 0, 0, LINE, 10, 10, LINE, 0, 10, LINE, 0, 0, CLOSE])
        #expect(Vector.remove(Vector.contours([MOVE, 0, 0, LINE, 1, 1]), [Vector.At(0, 0)]).isEmpty)
    }

    @Test func aMovedKnotTakesItsHandlesAlongAMovedHandleOnlyItself() {
        let cs = Vector.contours(arc)
        let k = Vector.shift(cs, [Vector.At(0, 1)], .point, 1, 2)[0].knots[1]
        #expect((k.x, k.y, k.ix, k.iy) == (11, 12, 6, 12))
        let h = Vector.shift(cs, [Vector.At(0, 0)], .out, 1, 0)[0].knots[0]
        #expect((h.x, h.y, h.ox, h.oy) == (0, 0, 1, 5))
    }

    @Test func aSmoothKnotGetsHandlesAlongItsNeighboursAndACornerNone() {
        let cs = Vector.contours(square)
        let smooth = Vector.smooth(cs, Vector.At(0, 1), true)
        #expect(smooth[0].knots[1].curved)
        let k = smooth[0].knots[1]
        // Along the line from (0, 0) to (10, 10).
        #expect(abs((k.ox - k.x) - (k.oy - k.y)) < 1e-9)
        #expect(!Vector.smooth(smooth, Vector.At(0, 1), false)[0].knots[1].curved)
    }

    @Test func penAnchorsMakeLinesCurvesAndCloseOnTheFirst() {
        typealias A = Vector.Anchor
        #expect(Vector.penPath([A(x: 0, y: 0), A(x: 10, y: 0)], closed: false) == [MOVE, 0, 0, LINE, 10, 0])
        #expect(Vector.penPath([A(x: 0, y: 0), A(x: 10, y: 0, hx: 0, hy: 5), A(x: 20, y: 0)], closed: false)
            == [MOVE, 0, 0, CUBIC, 0, 0, 10, -5, 10, 0, CUBIC, 10, 5, 20, 0, 20, 0])
        #expect(Vector.penPath([A(x: 0, y: 0), A(x: 10, y: 0), A(x: 0, y: 10)], closed: true)
            == [MOVE, 0, 0, LINE, 10, 0, LINE, 0, 10, LINE, 0, 0, CLOSE])
    }
}
