import CoreGraphics
import Foundation

// The handles of the selection on the canvas; see `web/src/handles.ts`. Points in
// "screen space" are canvas points.

public enum Handle: Equatable, Hashable, Sendable {
    /// A corner or edge of the box: "n", "ne", "e" and so on.
    case resize(String)
    /// Just outside a corner such as "nw": turns the selection.
    case rotate(String)
    /// An end of a line.
    case end(Int)
    /// A corner radius, from the top left clockwise.
    case radius(Int)
    /// Between two layers of a row.
    case gap(XY, Int)
}

/// A gap handle in screen space between two layers of a row along `axis`.
public struct GapHandle: Equatable, Sendable {
    public var point: CGPoint
    public var axis: XY
}

public enum Handles {
    /// The side of a square handle in points.
    public static let size: Double = 8
    /// Distance from an edge within which it is grabbed.
    static let edge: Double = 4
    /// Distance beyond a corner within which the selection turns.
    static let turn: Double = 16
    /// Least distance of a radius handle from its corner; below 4 times it they hide.
    static let radius: Double = 12
    static let portInset: Double = 16
    public static let port: Double = 10

    /// `p` turned `degrees` counterclockwise around `c`, as the engine turns layers.
    public static func spin(_ p: CGPoint, _ degrees: Double, around c: CGPoint = .zero) -> CGPoint {
        let (s, k) = (sin(degrees * .pi / 180), cos(degrees * .pi / 180))
        let (x, y) = (p.x - c.x, p.y - c.y)
        return CGPoint(x: c.x + k * x + s * y, y: c.y - s * x + k * y)
    }

    /// The upright box around the turned box `b`.
    public static func upright(_ b: Box) -> Box {
        let c = b.center
        let ps = [(0.0, 0.0), (b.w, 0), (b.w, b.h), (0, b.h)].map { spin(CGPoint(x: b.x + $0.0, y: b.y + $0.1), b.rotation, around: c) }
        let xs = ps.map(\.x)
        let ys = ps.map(\.y)
        return Box(x: xs.min()!, y: ys.min()!, w: xs.max()! - xs.min()!, h: ys.max()! - ys.min()!)
    }

    public static func rect(_ a: CGPoint, _ b: CGPoint) -> Box {
        Box(x: min(a.x, b.x), y: min(a.y, b.y), w: abs(a.x - b.x), h: abs(a.y - b.y))
    }

    /// What the canvas point `q` grabs of the selection's handles. Radius handles are in
    /// the unturned space of the box.
    public static func at(
        _ view: Viewport, _ q: CGPoint, box: Box? = nil, line: (CGPoint, CGPoint)? = nil, radii: [CGPoint] = [], gaps: [GapHandle] = []
    ) -> Handle? {
        if let g = gaps.firstIndex(where: { hypot($0.point.x - q.x, $0.point.y - q.y) <= size }) {
            return .gap(gaps[g].axis, g)
        }
        var p = q
        if let box, box.rotation != 0 {
            p = spin(p, -box.rotation, around: view.toCanvas(box.center))
        }
        if let i = radii.firstIndex(where: { hypot($0.x - p.x, $0.y - p.y) <= size + 1 }) { return .radius(i) }
        if let line {
            let (a, b) = (view.toCanvas(line.0), view.toCanvas(line.1))
            if hypot(a.x - p.x, a.y - p.y) <= size / 2 + 1 { return .end(0) }
            if hypot(b.x - p.x, b.y - p.y) <= size / 2 + 1 { return .end(1) }
            func beyond(_ e: CGPoint, _ o: CGPoint) -> Bool {
                hypot(e.x - p.x, e.y - p.y) <= turn && (p.x - e.x) * (e.x - o.x) + (p.y - e.y) * (e.y - o.y) > 0
            }
            return beyond(a, b) ? .rotate("nw") : beyond(b, a) ? .rotate("se") : nil
        }
        guard let box else { return nil }
        let tl = view.toCanvas(CGPoint(x: box.x, y: box.y))
        let (l, t) = (tl.x, tl.y)
        let r = l + box.w * view.zoom
        let b = t + box.h * view.zoom
        func near(_ v: Double, _ a: Double, _ d: Double) -> Bool { abs(v - a) <= d }
        func within(_ v: Double, _ a: Double, _ c: Double) -> Bool { v >= a - edge && v <= c + edge }
        let v = box.h == 0 ? "" : near(p.y, t, size / 2) ? "n" : near(p.y, b, size / 2) ? "s" : ""
        let h = box.w == 0 ? "" : near(p.x, l, size / 2) ? "w" : near(p.x, r, size / 2) ? "e" : ""
        if !v.isEmpty && !h.isEmpty { return .resize(v + h) }
        if !within(p.x, l, r) || !within(p.y, t, b) {
            for (cy, v) in [(t, "n"), (b, "s")] {
                for (cx, h) in [(l, "w"), (r, "e")] where hypot(p.x - cx, p.y - cy) <= turn { return .rotate(v + h) }
            }
            return nil
        }
        if box.h != 0 && near(p.y, t, edge) { return .resize("n") }
        if box.h != 0 && near(p.y, b, edge) { return .resize("s") }
        if box.w != 0 && near(p.x, l, edge) { return .resize("w") }
        if box.w != 0 && near(p.x, r, edge) { return .resize("e") }
        return nil
    }

    /// The gap handles in screen space of a row of `boxes` along `axis`.
    public static func gapHandles(_ view: Viewport, axis: XY, _ boxes: [Box]) -> [GapHandle] {
        boxes.indices.dropFirst().map { i in
            let (a, b) = (boxes[i - 1], boxes[i])
            let p = axis == .x
                ? CGPoint(x: (a.x + a.w + b.x) / 2, y: (max(a.y, b.y) + min(a.y + a.h, b.y + b.h)) / 2)
                : CGPoint(x: (max(a.x, b.x) + min(a.x + a.w, b.x + b.w)) / 2, y: (a.y + a.h + b.y) / 2)
            return GapHandle(point: view.toCanvas(p), axis: axis)
        }
    }

    /// The corner radius handles in screen space of `box` with `radii`, from the top left clockwise.
    public static func radiusHandles(_ view: Viewport, _ box: Box, radii: [Double]) -> [CGPoint] {
        let (w, h) = (box.w * view.zoom, box.h * view.zoom)
        guard min(w, h) >= 4 * radius else { return [] }
        let tl = view.toCanvas(CGPoint(x: box.x, y: box.y))
        return radii.enumerated().map { i, r in
            let d = min(max(r * view.zoom, radius), w / 2, h / 2)
            return CGPoint(x: i == 1 || i == 2 ? tl.x + w - d : tl.x + d, y: i < 2 ? tl.y + d : tl.y + h - d)
        }
    }

    /// The in- and out-port in screen space of a text frame placed on its spread, as in
    /// InDesign: on its left edge below the top and its right edge above the bottom.
    public static func ports(_ view: Viewport, _ n: Box) -> (in: CGPoint, out: CGPoint) {
        let inset = min(portInset / view.zoom, n.h / 2)
        let c = n.center
        func at(_ x: Double, _ y: Double) -> CGPoint { view.toCanvas(spin(CGPoint(x: x, y: y), n.rotation, around: c)) }
        return (at(n.x, n.y + inset), at(n.x + n.w, n.y + n.h - inset))
    }

    public enum Port: Sendable { case `in`, out }

    /// The port of `ports` at the canvas point `q`.
    public static func port(_ ports: (in: CGPoint?, out: CGPoint), at q: CGPoint) -> Port? {
        func near(_ p: CGPoint?) -> Bool {
            guard let p else { return false }
            return abs(p.x - q.x) <= port / 2 + 1 && abs(p.y - q.y) <= port / 2 + 1
        }
        return near(ports.out) ? .out : near(ports.in) ? .in : nil
    }

    /// The boxes of `frames` in the selection box `box` after its `handle` was dragged
    /// by `d`: `alt` resizes about the centre, `shift` keeps the proportions. Everything
    /// is in the space of the spread.
    public static func resized(_ box: Box, handle: String, by d: CGPoint, alt: Bool, shift: Bool, frames: [Box]) -> [Box] {
        var l = box.x + (handle.contains("w") ? d.x : 0)
        var r = box.x + box.w + (handle.contains("e") ? d.x : 0)
        var t = box.y + (handle.contains("n") ? d.y : 0)
        var b = box.y + box.h + (handle.contains("s") ? d.y : 0)
        if alt {
            if handle.contains("w") { r = box.x + box.w - d.x }
            if handle.contains("e") { l = box.x - d.x }
            if handle.contains("n") { b = box.y + box.h - d.y }
            if handle.contains("s") { t = box.y - d.y }
        }
        if shift && box.w != 0 && box.h != 0 {
            let sw = abs((r - l) / box.w)
            let sh = abs((b - t) / box.h)
            let vertical = handle.contains("n") || handle.contains("s")
            let horizontal = handle.contains("e") || handle.contains("w")
            let s = !vertical ? sw : !horizontal ? sh : max(sw, sh)
            let cx = handle.contains("w") ? r : handle.contains("e") ? l : (l + r) / 2
            let cy = handle.contains("n") ? b : handle.contains("s") ? t : (t + b) / 2
            let w = box.w * s * sign(r - l)
            let h = box.h * s * sign(b - t)
            (l, r) = handle.contains("w") ? (cx - w, cx) : handle.contains("e") ? (cx, cx + w) : (cx - w / 2, cx + w / 2)
            (t, b) = handle.contains("n") ? (cy - h, cy) : handle.contains("s") ? (cy, cy + h) : (cy - h / 2, cy + h / 2)
        }
        let sx = box.w != 0 ? (r - l) / box.w : 1
        let sy = box.h != 0 ? (b - t) / box.h : 1
        return frames.map { n in
            let x = l + (n.x - box.x) * sx
            let y = t + (n.y - box.y) * sy
            return rect(CGPoint(x: x, y: y), CGPoint(x: x + n.w * sx, y: y + n.h * sy))
        }
    }

    /// The sign of `v`, 1 for 0, as `Math.sign(v || 1)`.
    private static func sign(_ v: Double) -> Double { v < 0 ? -1 : 1 }
}
