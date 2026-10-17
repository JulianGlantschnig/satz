import Foundation

/// The points of display-list paths and what the pen and the path edit mode do to them;
/// see `web/src/vector.ts` and `web/src/pen.ts`.
public enum Vector {
    static let move = 0.0, line = 1.0, cubic = 4.0, close = 5.0

    /// A point of a path with the handles of its incoming and outgoing curve; a handle on
    /// the point is none.
    public struct Knot: Equatable, Sendable {
        public var x, y, ix, iy, ox, oy: Double

        public init(x: Double, y: Double, ix: Double, iy: Double, ox: Double, oy: Double) {
            (self.x, self.y, self.ix, self.iy, self.ox, self.oy) = (x, y, ix, iy, ox, oy)
        }

        public init(_ x: Double, _ y: Double) { self.init(x: x, y: y, ix: x, iy: y, ox: x, oy: y) }

        /// Whether the knot has a handle off its point.
        public var curved: Bool { ix != x || iy != y || ox != x || oy != y }

        public var point: CGPoint { CGPoint(x: x, y: y) }

        /// The knot with all its points mapped by `f`.
        public func mapped(_ f: (Double, Double) -> (Double, Double)) -> Knot {
            let (a, b) = f(x, y), (c, d) = f(ix, iy), (e, g) = f(ox, oy)
            return Knot(x: a, y: b, ix: c, iy: d, ox: e, oy: g)
        }
    }

    public struct Contour: Equatable, Sendable {
        public var knots: [Knot]
        public var closed: Bool

        public init(knots: [Knot], closed: Bool) {
            self.knots = knots
            self.closed = closed
        }
    }

    /// Knot `i` of contour `c`.
    public struct At: Hashable, Sendable {
        public var c: Int
        public var i: Int
        public init(_ c: Int, _ i: Int) { (self.c, self.i) = (c, i) }
    }

    /// The part of a knot that a drag moves.
    public enum Part: Sendable { case point, `in`, out }

    static func isLine(_ a: Knot, _ b: Knot) -> Bool { a.ox == a.x && a.oy == a.y && b.ix == b.x && b.iy == b.y }

    /// The contours of the display-list path `path`.
    public static func contours(_ path: [Double]) -> [Contour] {
        var out: [Contour] = []
        var i = 0
        while i < path.count {
            switch path[i] {
            case move where i + 2 < path.count:
                out.append(Contour(knots: [Knot(path[i + 1], path[i + 2])], closed: false))
                i += 3
            case line where i + 2 < path.count && !out.isEmpty:
                out[out.count - 1].knots.append(Knot(path[i + 1], path[i + 2]))
                i += 3
            case cubic where i + 6 < path.count && !out.isEmpty:
                let last = out[out.count - 1].knots.count - 1
                out[out.count - 1].knots[last].ox = path[i + 1]
                out[out.count - 1].knots[last].oy = path[i + 2]
                var k = Knot(path[i + 5], path[i + 6])
                (k.ix, k.iy) = (path[i + 3], path[i + 4])
                out[out.count - 1].knots.append(k)
                i += 7
            case close where !out.isEmpty:
                out[out.count - 1].closed = true
                var knots = out[out.count - 1].knots
                if knots.count > 1, let first = knots.first, let last = knots.last, hypot(first.x - last.x, first.y - last.y) < 1e-3 {
                    (knots[0].ix, knots[0].iy) = (last.ix, last.iy)
                    knots.removeLast()
                }
                out[out.count - 1].knots = knots
                i += 1
            default:
                return out
            }
        }
        return out
    }

    /// The display-list path of `cs`.
    public static func path(_ cs: [Contour]) -> [Double] {
        var path: [Double] = []
        func segment(_ a: Knot, _ b: Knot) {
            if isLine(a, b) { path += [line, b.x, b.y] } else { path += [cubic, a.ox, a.oy, b.ix, b.iy, b.x, b.y] }
        }
        for c in cs where !c.knots.isEmpty {
            path += [move, c.knots[0].x, c.knots[0].y]
            for i in c.knots.indices.dropFirst() { segment(c.knots[i - 1], c.knots[i]) }
            if c.closed {
                segment(c.knots[c.knots.count - 1], c.knots[0])
                path.append(close)
            }
        }
        return path
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }

    static func bezier(_ a: Knot, _ b: Knot, _ t: Double) -> (p01: CGPoint, p23: CGPoint, p012: CGPoint, p123: CGPoint, p: CGPoint) {
        let (p0, p1, p2, p3) = (a.point, CGPoint(x: a.ox, y: a.oy), CGPoint(x: b.ix, y: b.iy), b.point)
        let (p01, p12, p23) = (lerp(p0, p1, t), lerp(p1, p2, t), lerp(p2, p3, t))
        let (p012, p123) = (lerp(p01, p12, t), lerp(p12, p23, t))
        return (p01, p23, p012, p123, lerp(p012, p123, t))
    }

    /// The segments of `cs` as the knot each starts at, and the knot it ends at.
    static func segments(_ cs: [Contour]) -> [(at: At, a: Knot, b: Knot)] {
        cs.enumerated().flatMap { c, contour in
            contour.knots.indices.compactMap { i in
                let n = contour.knots.count
                guard i + 1 < n || (contour.closed && n > 1) else { return nil }
                return (At(c, i), contour.knots[i], contour.knots[(i + 1) % n])
            }
        }
    }

    /// The segment of `cs` nearest `p`, by the knot it starts at, where on it and how far away.
    public static func nearest(_ cs: [Contour], _ p: CGPoint) -> (at: At, t: Double, d: Double) {
        var best = (at: At(0, 0), t: 0.0, d: Double.infinity)
        for s in segments(cs) {
            for k in 1..<64 {
                let q = bezier(s.a, s.b, Double(k) / 64).p
                let d = hypot(q.x - p.x, q.y - p.y)
                if d < best.d { best = (s.at, Double(k) / 64, d) }
            }
        }
        return best
    }

    /// `cs` with a knot at `t` on the segment after the knot `at`, which becomes `[c, i + 1]`.
    public static func split(_ cs: [Contour], _ at: At, _ t: Double) -> [Contour] {
        var out = cs
        var knots = out[at.c].knots
        let j = (at.i + 1) % knots.count
        let (a, b) = (knots[at.i], knots[j])
        let s = bezier(a, b, t)
        let straight = isLine(a, b)
        if !straight {
            (knots[at.i].ox, knots[at.i].oy) = (s.p01.x, s.p01.y)
            (knots[j].ix, knots[j].iy) = (s.p23.x, s.p23.y)
        }
        knots.insert(straight ? Knot(s.p.x, s.p.y) : Knot(x: s.p.x, y: s.p.y, ix: s.p012.x, iy: s.p012.y, ox: s.p123.x, oy: s.p123.y), at: at.i + 1)
        out[at.c].knots = knots
        return out
    }

    /// `cs` without the knots `at`, and without a contour once that has fewer than 2 knots.
    public static func remove(_ cs: [Contour], _ at: Set<At>) -> [Contour] {
        cs.enumerated().map { c, contour in
            Contour(knots: contour.knots.enumerated().filter { !at.contains(At(c, $0.offset)) }.map(\.element), closed: contour.closed)
        }.filter { $0.knots.count > 1 }
    }

    /// `cs` with the knot `at` smooth, its handles along its neighbours a third of the way
    /// to each, or a corner without handles.
    public static func smooth(_ cs: [Contour], _ at: At, _ on: Bool) -> [Contour] {
        var out = cs
        let contour = out[at.c]
        let (knots, n, i) = (contour.knots, contour.knots.count, at.i)
        let k = knots[i]
        let prev = knots[contour.closed ? (i + n - 1) % n : max(i - 1, 0)]
        let next = knots[contour.closed ? (i + 1) % n : min(i + 1, n - 1)]
        let (dx, dy) = (next.x - prev.x, next.y - prev.y)
        let len = (hypot(dx, dy) == 0 ? 1 : hypot(dx, dy)) * 3
        let (a, b) = on ? (hypot(k.x - prev.x, k.y - prev.y) / len, hypot(next.x - k.x, next.y - k.y) / len) : (0, 0)
        out[at.c].knots[i] = Knot(x: k.x, y: k.y, ix: k.x - dx * a, iy: k.y - dy * a, ox: k.x + dx * b, oy: k.y + dy * b)
        return out
    }

    /// `cs` with the knots `at`, or with `part` only their handle, moved by (dx, dy).
    public static func shift(_ cs: [Contour], _ at: [At], _ part: Part, _ dx: Double, _ dy: Double) -> [Contour] {
        var out = cs
        for a in at where a.c < out.count && a.i < out[a.c].knots.count {
            var k = out[a.c].knots[a.i]
            if part != .out { (k.ix, k.iy) = (k.ix + dx, k.iy + dy) }
            if part != .in { (k.ox, k.oy) = (k.ox + dx, k.oy + dy) }
            if part == .point { (k.x, k.y) = (k.x + dx, k.y + dy) }
            out[a.c].knots[a.i] = k
        }
        return out
    }

    /// A pen point in pt; (hx, hy) is its outgoing handle, the incoming one is mirrored.
    public struct Anchor: Equatable, Sendable {
        public var x, y, hx, hy: Double
        public init(x: Double, y: Double, hx: Double = 0, hy: Double = 0) { (self.x, self.y, self.hx, self.hy) = (x, y, hx, hy) }
    }

    /// The display-list path through the pen's anchors.
    public static func penPath(_ anchors: [Anchor], closed: Bool) -> [Double] {
        guard let first = anchors.first else { return [] }
        var path = [move, first.x, first.y]
        func segment(_ a: Anchor, _ b: Anchor) {
            if a.hx == 0 && a.hy == 0 && b.hx == 0 && b.hy == 0 {
                path += [line, b.x, b.y]
            } else {
                path += [cubic, a.x + a.hx, a.y + a.hy, b.x - b.hx, b.y - b.hy, b.x, b.y]
            }
        }
        for i in anchors.indices.dropFirst() { segment(anchors[i - 1], anchors[i]) }
        if closed, let last = anchors.last {
            segment(last, first)
            path.append(close)
        }
        return path
    }
}
