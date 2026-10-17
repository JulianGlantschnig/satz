import SatzCore
import SwiftUI

extension Editor {
    /// The frame whose auto layout places `n`, if one does.
    func flow(of n: Node) -> Node? {
        guard let parent = nodes[n.id]?.parent, parent.kind == .frame, parent.direction != .none, !n.absolute else { return nil }
        return parent
    }

    /// Adds auto layout to the selection: a frame lays out its children, other layers go
    /// into a new frame that does; see `autoLayout` in `engine/src/doc`.
    func addAutoLayout() {
        guard !selection.isEmpty else { return }
        let made = apply(.autoLayout(selection))
        if !made.isEmpty { select(made) }
    }

    func removeAutoLayout() {
        batch {
            for n in selected where n.kind == .frame && n.direction != .none {
                apply(.set(id: n.id, ["direction": .string(Direction.none.rawValue)]))
            }
        }
    }

    /// Where the layers `ids` dragged to `p` (in the page's space) land among the other
    /// children of the auto layout frame `parent`: the index for a move and the insertion
    /// line; see `insertion` in `web/src/editor.ts`.
    static func insertion(_ parent: Node, _ ids: [String], _ p: CGPoint) -> (index: Int, line: (CGPoint, CGPoint)) {
        let horizontal = parent.direction == .horizontal
        let others = (parent.children ?? []).filter { !ids.contains($0.id) }
        let flow = others.filter { !$0.absolute }
        func main(_ n: Node) -> Double { horizontal ? n.x + n.w / 2 : n.y + n.h / 2 }
        let next = flow.first { main($0) > (horizontal ? p.x : p.y) }
        let index = next.flatMap { n in others.firstIndex { $0.id == n.id } } ?? others.count
        let at = next.flatMap { n in flow.firstIndex { $0.id == n.id } } ?? flow.count
        let prev = at > 0 ? flow[at - 1] : nil
        let line: Double
        switch (prev, next) {
        case let (prev?, next?): line = horizontal ? (prev.x + prev.w + next.x) / 2 : (prev.y + prev.h + next.y) / 2
        case let (nil, next?): line = horizontal ? next.x : next.y
        case let (prev?, nil): line = horizontal ? prev.x + prev.w : prev.y + prev.h
        case (nil, nil): line = horizontal ? parent.x : parent.y
        }
        return horizontal
            ? (index, (CGPoint(x: line, y: parent.y), CGPoint(x: line, y: parent.y + parent.h)))
            : (index, (CGPoint(x: parent.x, y: line), CGPoint(x: parent.x + parent.w, y: line)))
    }

    /// The innermost shown auto layout frame at `p` on the spread outside the layers `ids`.
    func flowFrame(at p: CGPoint, outside ids: [String]) -> Node? {
        func depth(_ id: String) -> Int {
            var (d, e) = (0, nodes[id])
            while let up = e?.parent {
                d += 1
                e = nodes[up.id]
            }
            return d
        }
        func inside(_ id: String) -> Bool {
            var e = nodes[id]
            while let n = e?.node {
                if ids.contains(n.id) { return true }
                e = e?.parent.flatMap { nodes[$0.id] }
            }
            return false
        }
        return nodes.values.map(\.node)
            .filter { $0.kind == .frame && $0.direction != .none && !$0.hidden && !$0.locked && placed($0).contains(p) && !inside($0.id) }
            .max { depth($0.id) < depth($1.id) }
    }

    /// The centres that a drag swaps: of several selected layers, or of the layers in a
    /// selected group or auto layout frame.
    func swappable() -> [Node] {
        guard tool == .move, editing == nil else { return [] }
        let list: [Node]
        if selection.count > 1 {
            list = selected
        } else if let one = selected.first, one.kind == .group || (one.kind == .frame && one.direction != .none) {
            list = (one.children ?? []).filter { !$0.hidden && !$0.absolute }
        } else {
            list = []
        }
        return list.count < 2 ? [] : list
    }

    /// Swaps the places of the layers `a` and `b`, in the order of an auto layout frame they share.
    func swap(_ a: String, _ b: String) {
        guard let p = nodes[a], let q = nodes[b] else { return }
        batch {
            if let flow = p.parent, flow.id == q.parent?.id, flow.kind == .frame, flow.direction != .none, let kids = flow.children,
                let i = kids.firstIndex(where: { $0.id == a }), let j = kids.firstIndex(where: { $0.id == b })
            {
                let (lo, hi) = (min(i, j), max(i, j))
                let (low, high) = (kids[lo].id, kids[hi].id)
                apply(.move([high], parent: flow.id, index: lo))
                apply(.move([low], parent: flow.id, index: hi))
            } else {
                let (m, n) = (p.node, q.node)
                apply(.setFrame(id: m.id, x: n.x, y: n.y, w: m.w, h: m.h))
                apply(.setFrame(id: n.id, x: m.x, y: m.y, w: n.w, h: n.h))
            }
        }
    }
}
