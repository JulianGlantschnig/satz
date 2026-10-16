import CoreGraphics
import Foundation

// What layers snap to and the distances shown while they move; see `web/src/snap.ts`.

/// A box, turned `rotation` degrees counterclockwise around its centre.
public struct Box: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public var rotation: Double

    public init(x: Double, y: Double, w: Double, h: Double, rotation: Double = 0) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.rotation = rotation
    }

    public init(_ r: CGRect) { self.init(x: r.minX, y: r.minY, w: r.width, h: r.height) }

    public var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    public var center: CGPoint { CGPoint(x: x + w / 2, y: y + h / 2) }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }

    public func grown(by m: Double) -> Box { Box(x: x - m, y: y - m, w: w + 2 * m, h: h + 2 * m, rotation: rotation) }

    public func contains(_ p: CGPoint) -> Bool { p.x >= x && p.x <= x + w && p.y >= y && p.y <= y + h }

    /// The box around `boxes`.
    public static func around(_ boxes: [Box]) -> Box {
        guard let first = boxes.first else { return Box(x: 0, y: 0, w: 0, h: 0) }
        var (l, t, r, b) = (first.x, first.y, first.maxX, first.maxY)
        for o in boxes.dropFirst() {
            l = min(l, o.x)
            t = min(t, o.y)
            r = max(r, o.maxX)
            b = max(b, o.maxY)
        }
        return Box(x: l, y: t, w: r - l, h: b - t)
    }
}

/// A line to snap to at `at` on its axis, spanning `from` to `to` on the other.
public struct SnapLine: Equatable, Sendable {
    public var at: Double
    public var from: Double
    public var to: Double
    public init(at: Double, from: Double, to: Double) {
        self.at = at
        self.from = from
        self.to = to
    }
}

public struct SnapLines: Equatable, Sendable {
    public var x: [SnapLine] = []
    public var y: [SnapLine] = []
    public init(x: [SnapLine] = [], y: [SnapLine] = []) {
        self.x = x
        self.y = y
    }
}

public enum Axis: Sendable { case x, y }

/// A guide along x = `at` or y = `at`, from `from` to `to` on the other axis.
public struct SnapGuide: Equatable, Sendable {
    public var axis: Axis
    public var at: Double
    public var from: Double
    public var to: Double
}

/// A distance from (x1, y1) to (x2, y2); a dashed one only leads to what is measured.
public struct Measure: Equatable, Sendable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double
    public var length: Double
    public var dashed = false
    public var arrow: String?

    public init(x1: Double, y1: Double, x2: Double, y2: Double, length: Double, dashed: Bool = false, arrow: String? = nil) {
        (self.x1, self.y1, self.x2, self.y2, self.length, self.dashed, self.arrow) = (x1, y1, x2, y2, length, dashed, arrow)
    }
}

/// A layer as snapping sees it: its box, and for upright text frames their insets,
/// columns and baseline grid.
public struct SnapTarget: Sendable {
    public var box: Box
    public var text: Node?

    public init(box: Box, text: Node? = nil) {
        self.box = box
        self.text = text
    }
}

public enum Snap {
    static let epsilon = 1e-6

    /// What layers snap to on a spread: edges and centres of the pages and of `nodes`,
    /// of text frames also their insets, column edges and baseline grid unless turned,
    /// and with `grids` the guides and layout grids. Everything is in the spread's space.
    public static func targets(_ sheets: [Sheet], _ nodes: [SnapTarget], grids: Bool = false) -> SnapLines {
        var out = SnapLines()
        func box(_ b: Box) {
            for at in [b.x, b.x + b.w / 2, b.x + b.w] { out.x.append(SnapLine(at: at, from: b.y, to: b.y + b.h)) }
            for at in [b.y, b.y + b.h / 2, b.y + b.h] { out.y.append(SnapLine(at: at, from: b.x, to: b.x + b.w)) }
        }
        for s in sheets {
            box(Box(x: s.x, y: 0, w: s.width, h: s.height))
            guard grids else { continue }
            for at in s.guides.x { out.x.append(SnapLine(at: s.x + at, from: 0, to: s.height)) }
            for at in s.guides.y { out.y.append(SnapLine(at: at, from: s.x, to: s.x + s.width)) }
            let spans = s.gridSpans()
            for at in spans.x.flatMap({ [$0.from, $0.to] }) { out.x.append(SnapLine(at: at, from: 0, to: s.height)) }
            for at in spans.y.flatMap({ [$0.from, $0.to] }) { out.y.append(SnapLine(at: at, from: s.x, to: s.x + s.width)) }
        }
        for t in nodes {
            let n = t.box
            box(n)
            guard let text = t.text, text.kind == .text, n.rotation == 0 else { continue }
            let l = n.x + (text.insetLeft ?? 0)
            let r = n.x + n.w - (text.insetRight ?? 0)
            let top = n.y + (text.insetTop ?? 0)
            let b = n.y + n.h - (text.insetBottom ?? 0)
            let columns = max(1, text.columns ?? 1)
            let gutter = text.gutter ?? 0
            let column = (r - l - gutter * Double(columns - 1)) / Double(columns)
            for c in 0..<columns {
                let at = l + Double(c) * (column + gutter)
                out.x.append(SnapLine(at: at, from: n.y, to: n.y + n.h))
                out.x.append(SnapLine(at: at + column, from: n.y, to: n.y + n.h))
            }
            out.y.append(SnapLine(at: top, from: n.x, to: n.x + n.w))
            out.y.append(SnapLine(at: b, from: n.x, to: n.x + n.w))
            let grid = text.baselineGrid ?? 0
            if grid > 0 {
                var at = top + (text.baselineStart ?? 0)
                while at <= b + epsilon {
                    out.y.append(SnapLine(at: at, from: l, to: r))
                    at += grid
                }
            }
        }
        return out
    }

    /// The offset that moves the nearest of `values` onto one of `lines` within `tolerance`, or 0.
    public static func snap(_ values: [Double], _ lines: [SnapLine], tolerance: Double) -> Double {
        var best = 0.0
        var away = tolerance + epsilon
        for v in values {
            for l in lines {
                let d = l.at - v
                if abs(d) < away { (best, away) = (d, abs(d)) }
            }
        }
        return best
    }

    /// Guides through each of `xs` and `ys` that lies on one of `lines`, spanning the line and `box`.
    public static func guides(_ box: Box, _ lines: SnapLines, xs: [Double], ys: [Double]) -> [SnapGuide] {
        var out: [SnapGuide] = []
        func along(_ axis: Axis, _ values: [Double], _ list: [SnapLine], _ from: Double, _ to: Double) {
            var seen = Set<Double>()
            for at in values where seen.insert(at).inserted {
                let on = list.filter { abs($0.at - at) < epsilon }
                if !on.isEmpty {
                    out.append(SnapGuide(axis: axis, at: at, from: min(from, on.map(\.from).min()!), to: max(to, on.map(\.to).max()!)))
                }
            }
        }
        along(.x, xs, lines.x, box.y, box.y + box.h)
        along(.y, ys, lines.y, box.x, box.x + box.w)
        return out
    }

    /// The `n` of `others` nearest to `box` that do not overlap it.
    public static func nearest(_ box: Box, _ others: [Box], n: Int = 2) -> [Box] {
        others
            .map { o -> (Box, Double) in
                let dx = max(o.x - box.x - box.w, box.x - o.x - o.w, 0)
                let dy = max(o.y - box.y - box.h, box.y - o.y - o.h, 0)
                return (o, hypot(dx, dy))
            }
            .filter { $0.1 > 0 }
            .enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 < $1.element.1 : $0.offset < $1.offset }
            .prefix(n)
            .map(\.element.0)
    }

    /// The distances between `a` and `b`: when one is inside the other, from each side
    /// of the inner one to the nearest of `others` on that side or else to the outer one;
    /// else across the gap on each axis they are apart on.
    public static func measure(_ a: Box, _ b: Box, others: [Box] = []) -> [Measure] {
        var out: [Measure] = []
        func h(_ x1: Double, _ x2: Double, _ y: Double) {
            if x2 - x1 > epsilon { out.append(Measure(x1: x1, y1: y, x2: x2, y2: y, length: x2 - x1)) }
        }
        func v(_ y1: Double, _ y2: Double, _ x: Double) {
            if y2 - y1 > epsilon { out.append(Measure(x1: x, y1: y1, x2: x, y2: y2, length: y2 - y1)) }
        }
        func inside(_ p: Box, _ q: Box) -> Bool {
            p.x >= q.x - epsilon && p.y >= q.y - epsilon && p.x + p.w <= q.x + q.w + epsilon && p.y + p.h <= q.y + q.h + epsilon
        }
        if inside(a, b) || inside(b, a) {
            let (i, u) = inside(a, b) ? (a, b) : (b, a)
            let (ir, ib, ur, ub) = (i.x + i.w, i.y + i.h, u.x + u.w, u.y + u.h)
            let row = others.filter { $0.y < ib && $0.y + $0.h > i.y }
            let column = others.filter { $0.x < ir && $0.x + $0.w > i.x }
            func y(_ o: Box?) -> Double { o.map { (max(i.y, $0.y) + min(ib, $0.y + $0.h)) / 2 } ?? i.y + i.h / 2 }
            func x(_ o: Box?) -> Double { o.map { (max(i.x, $0.x) + min(ir, $0.x + $0.w)) / 2 } ?? i.x + i.w / 2 }
            let l = row.filter { $0.x + $0.w <= i.x + epsilon && $0.x + $0.w > u.x }.max { $0.x + $0.w < $1.x + $1.w }
            let r = row.filter { $0.x >= ir - epsilon && $0.x < ur }.min { $0.x < $1.x }
            let t = column.filter { $0.y + $0.h <= i.y + epsilon && $0.y + $0.h > u.y }.max { $0.y + $0.h < $1.y + $1.h }
            let d = column.filter { $0.y >= ib - epsilon && $0.y < ub }.min { $0.y < $1.y }
            h(l.map { $0.x + $0.w } ?? u.x, i.x, y(l))
            h(ir, r?.x ?? ur, y(r))
            v(t.map { $0.y + $0.h } ?? u.y, i.y, x(t))
            v(ib, d?.y ?? ub, x(d))
            return out
        }
        let oy = (max(a.y, b.y), min(a.y + a.h, b.y + b.h))
        let ox = (max(a.x, b.x), min(a.x + a.w, b.x + b.w))
        if b.x >= a.x + a.w || a.x >= b.x + b.w {
            let right = b.x >= a.x + a.w
            let (l, r) = right ? (a.x + a.w, b.x) : (b.x + b.w, a.x)
            let y = oy.0 < oy.1 ? (oy.0 + oy.1) / 2 : a.y + a.h / 2
            h(l, r, y)
            if oy.0 >= oy.1 {
                let x = right ? b.x : b.x + b.w
                let to = b.y > y ? b.y : b.y + b.h
                out.append(Measure(x1: x, y1: y, x2: x, y2: to, length: abs(to - y), dashed: true))
            }
        }
        if b.y >= a.y + a.h || a.y >= b.y + b.h {
            let below = b.y >= a.y + a.h
            let (t, u) = below ? (a.y + a.h, b.y) : (b.y + b.h, a.y)
            let x = ox.0 < ox.1 ? (ox.0 + ox.1) / 2 : a.x + a.w / 2
            v(t, u, x)
            if ox.0 >= ox.1 {
                let y = below ? b.y : b.y + b.h
                let to = b.x > x ? b.x : b.x + b.w
                out.append(Measure(x1: x, y1: y, x2: to, y2: y, length: abs(to - x), dashed: true))
            }
        }
        return out
    }

    private struct Row {
        var before: Box?
        var after: Box?
        var gaps: [(m: Box, n: Box, d: Double)]
    }

    private static func start(_ b: Box, _ axis: Axis) -> Double { axis == .x ? b.x : b.y }
    private static func size(_ b: Box, _ axis: Axis) -> Double { axis == .x ? b.w : b.h }
    private static func end(_ b: Box, _ axis: Axis) -> Double { start(b, axis) + size(b, axis) }

    /// On `axis`, the layers of `others` in the row or column of `box` before and after
    /// it, and the gaps between neighbouring others in that row or column that `box`
    /// does not lie in.
    private static func row(_ box: Box, _ others: [Box], _ axis: Axis) -> Row {
        let across: Axis = axis == .x ? .y : .x
        let line = others
            .filter { start($0, across) < end(box, across) && end($0, across) > start(box, across) }
            .sorted { start($0, axis) < start($1, axis) }
        let before = line.filter { end($0, axis) <= start(box, axis) + epsilon }.max { end($0, axis) < end($1, axis) }
        let after = line.first { start($0, axis) >= end(box, axis) - epsilon }
        var gaps: [(Box, Box, Double)] = []
        for i in line.indices.dropFirst() {
            let (m, n) = (line[i - 1], line[i])
            let d = start(n, axis) - end(m, axis)
            if d > epsilon && (end(box, axis) <= end(m, axis) + epsilon || start(box, axis) >= start(n, axis) - epsilon) {
                gaps.append((m, n, d))
            }
        }
        return Row(before: before, after: after, gaps: gaps)
    }

    /// Starts of `box` on `axis` that leave it as far from a neighbour as two others in
    /// its row or column are apart, or midway between its neighbours.
    public static func spacings(_ box: Box, _ others: [Box], axis: Axis) -> [Double] {
        let r = row(box, others, axis)
        var out: [Double] = r.gaps.flatMap { g -> [Double] in
            (r.before.map { [end($0, axis) + g.d] } ?? []) + (r.after.map { [start($0, axis) - g.d - size(box, axis)] } ?? [])
        }
        if let b = r.before, let a = r.after { out.append((end(b, axis) + start(a, axis) - size(box, axis)) / 2) }
        return out
    }

    /// The distances on `axis` from `box` to its neighbours that equal the other one or
    /// a gap between others in its row or column, with those gaps.
    public static func equals(_ box: Box, _ others: [Box], axis: Axis) -> [Measure] {
        let r = row(box, others, axis)
        var near: [(m: Box, n: Box, d: Double)] = []
        if let b = r.before { near.append((b, box, start(box, axis) - end(b, axis))) }
        if let a = r.after { near.append((box, a, start(a, axis) - end(box, axis))) }
        let all = r.gaps + near.filter { $0.d > epsilon }
        func same(_ p: (m: Box, n: Box, d: Double), _ q: (m: Box, n: Box, d: Double)) -> Bool {
            p.m == q.m && p.n == q.n
        }
        var picked: [(m: Box, n: Box, d: Double)] = []
        for g in near {
            for o in all where !same(o, g) && abs(o.d - g.d) < 1e-3 && !picked.contains(where: { same($0, o) }) {
                picked.append(o)
            }
        }
        guard !picked.isEmpty else { return [] }
        for g in near where picked.contains(where: { abs($0.d - g.d) < 1e-3 }) && !picked.contains(where: { same($0, g) }) {
            picked.append(g)
        }
        return picked.flatMap { g in
            measure(g.m, g.n).filter { !$0.dashed && (axis == .x ? $0.y1 == $0.y2 : $0.x1 == $0.x2) }
        }
    }
}
