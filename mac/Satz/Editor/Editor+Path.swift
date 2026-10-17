import SatzCore
import SwiftUI

/// The path drawn with the pen: its layer and anchors in the space of its page.
struct Pen {
    var id: String
    var anchors: [Vector.Anchor]
}

/// The path whose points are edited: what a click does and the points picked.
struct PathEdit: Equatable {
    enum Mode: String, CaseIterable {
        case move, add, delete, fill

        /// Its key while the points are edited.
        var key: String {
            switch self {
            case .move: "v"
            case .add: "p"
            case .delete: "-"
            case .fill: "b"
            }
        }

        var symbol: String {
            switch self {
            case .move: "cursorarrow"
            case .add: "plus.circle"
            case .delete: "minus.circle"
            case .fill: "drop"
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .move: "Move Points"
            case .add: "Add Points"
            case .delete: "Delete Points"
            case .fill: "Fill Areas"
            }
        }
    }

    var id: String
    var mode = Mode.move
    var at: [Vector.At] = []
}

extension Editor {
    /// Starts a pen path at `p` on the spread in the page or frame `parent`, whose page
    /// sits `dx` right of the spine; it stays one undo step until it ends.
    func startPen(at p: CGPoint, parent: String, dx: Double) {
        beginGroup()
        guard let id = apply(.create(parent: parent, kind: .path, x: p.x - dx, y: p.y, w: 0, h: 0)).first else {
            endGroup()
            return
        }
        pen = Pen(id: id, anchors: [Vector.Anchor(x: p.x - dx, y: p.y)])
        select([])
        say(String(localized: "Return finishes · a click on the first point closes the path"))
    }

    /// Gives the pen path the anchors `anchors`.
    func setPen(_ anchors: [Vector.Anchor]) {
        guard var p = pen else { return }
        p.anchors = anchors
        pen = p
        apply(.setPath(id: p.id, path: Vector.penPath(anchors, closed: false)))
    }

    /// Ends the pen path, closed or open; one with fewer than two anchors goes.
    func finishPen(closed: Bool) {
        guard let p = pen else { return }
        pen = nil
        if p.anchors.count < 2 {
            apply(.delete([p.id]))
        } else {
            apply(.setPath(id: p.id, path: Vector.penPath(p.anchors, closed: closed)))
        }
        endGroup()
        if status?.error == false { clearStatus() }
        tool = .move
        select(p.anchors.count < 2 ? [] : [p.id])
    }

    /// Edits the points of the shape `id`, which becomes a path.
    func editPath(_ id: String) {
        guard let n = nodes[id]?.node, n.kind == .shape else { return }
        stopEditing()
        if n.shape != .path || n.rotation != 0 { apply(.flatten(id)) }
        select([id])
        vector = PathEdit(id: id)
    }

    /// The points of the path being edited, in the space of its page.
    func knots() -> [Vector.Contour] {
        guard let v = vector, let n = nodes[v.id]?.node, n.kind == .shape, n.shape == .path, let path = n.path else { return [] }
        return Vector.contours(path).map { c in
            Vector.Contour(knots: c.knots.map { $0.mapped { u, v in (n.x + u * n.w, n.y + v * n.h) } }, closed: c.closed)
        }
    }

    /// Gives the path being edited the points `cs` and picks `at`; without points the path goes.
    func setKnots(_ cs: [Vector.Contour], at: [Vector.At]? = nil) {
        guard var v = vector else { return }
        if cs.isEmpty {
            vector = nil
            apply(.delete([v.id]))
        } else {
            apply(.setPath(id: v.id, path: Vector.path(cs)))
            if let at { v.at = at }
            vector = v
        }
    }

    /// Makes the picked points smooth or corners.
    func smoothPicked(_ on: Bool) {
        guard let v = vector, !v.at.isEmpty else { return }
        setKnots(v.at.reduce(knots()) { Vector.smooth($0, $1, on) }, at: v.at)
    }

    /// Removes the picked points.
    func deletePicked() {
        guard let v = vector, !v.at.isEmpty else { return }
        setKnots(Vector.remove(knots(), Set(v.at)), at: [])
    }
}
