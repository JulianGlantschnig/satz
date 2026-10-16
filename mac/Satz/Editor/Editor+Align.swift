import Foundation
import SatzCore

/// Aligning, distributing and combining the selection; see `web/src/align.tsx`.
extension Editor {
    enum Align: String, CaseIterable, Identifiable {
        case left, center, right, top, middle, bottom, distributeX, distributeY, tidy

        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .left: "Align Left"
            case .center: "Align Horizontal Centers"
            case .right: "Align Right"
            case .top: "Align Top"
            case .middle: "Align Vertical Centers"
            case .bottom: "Align Bottom"
            case .distributeX: "Distribute Horizontally"
            case .distributeY: "Distribute Vertically"
            case .tidy: "Tidy Up"
            }
        }

        var symbol: String {
            switch self {
            case .left: "align.horizontal.left"
            case .center: "align.horizontal.center"
            case .right: "align.horizontal.right"
            case .top: "align.vertical.top"
            case .middle: "align.vertical.center"
            case .bottom: "align.vertical.bottom"
            case .distributeX: "distribute.horizontal.center"
            case .distributeY: "distribute.vertical.center"
            case .tidy: "square.grid.2x2"
            }
        }
    }

    /// Aligns the selection to its bounds, or a single layer to its parent frame or page;
    /// distributes three layers or more and tidies two or more.
    func align(_ how: Align) {
        let nodes = selected.filter { !$0.locked }
        guard let first = nodes.first, let home = self.nodes[first.id]?.page ?? page else { return }
        let to: Box
        if nodes.count > 1 {
            to = Box.around(nodes.map { Box(x: $0.x, y: $0.y, w: $0.w, h: $0.h) })
        } else if let parent = self.nodes[first.id]?.parent, parent.kind == .frame {
            to = Box(x: parent.x, y: parent.y, w: parent.w, h: parent.h)
        } else {
            to = Box(x: 0, y: 0, w: home.width, h: home.height)
        }
        var moves: [(Node, Double, Double)] = []
        func sorted(_ horizontal: Bool) -> [Node] {
            nodes.sorted { horizontal ? $0.x + $0.w / 2 < $1.x + $1.w / 2 : $0.y + $0.h / 2 < $1.y + $1.h / 2 }
        }
        switch how {
        case .distributeX, .distributeY:
            guard nodes.count >= 3 else { return }
            let horizontal = how == .distributeX
            let s = sorted(horizontal)
            let total = s.reduce(0) { $0 + (horizontal ? $1.w : $1.h) }
            let gap = ((horizontal ? to.w : to.h) - total) / Double(s.count - 1)
            var at = horizontal ? to.x : to.y
            for n in s {
                moves.append(horizontal ? (n, at, n.y) : (n, n.x, at))
                at += (horizontal ? n.w : n.h) + gap
            }
        case .tidy:
            guard nodes.count >= 2 else { return }
            var rows: [[Node]] = []
            for n in sorted(false) {
                if let row = rows.last, n.y + n.h / 2 < row.map({ $0.y + $0.h }).max()! {
                    rows[rows.count - 1].append(n)
                } else {
                    rows.append([n])
                }
            }
            rows = rows.map { $0.sorted { $0.x < $1.x } }
            let cw = nodes.map(\.w).max()!
            let rh = nodes.map(\.h).max()!
            let gaps = rows.flatMap { row in row.indices.dropFirst().map { row[$0].x - row[$0 - 1].x - row[$0 - 1].w } }.filter { $0 > 0 }
            let gap = gaps.min() ?? Units.mm(5)
            for (r, row) in rows.enumerated() {
                for (c, n) in row.enumerated() { moves.append((n, to.x + Double(c) * (cw + gap), to.y + Double(r) * (rh + gap))) }
            }
        default:
            for n in nodes {
                let x: Double = switch how {
                case .left: to.x
                case .center: to.x + (to.w - n.w) / 2
                case .right: to.x + to.w - n.w
                default: n.x
                }
                let y: Double = switch how {
                case .top: to.y
                case .middle: to.y + (to.h - n.h) / 2
                case .bottom: to.y + to.h - n.h
                default: n.y
                }
                moves.append((n, x, y))
            }
        }
        batch {
            for (n, x, y) in moves where x != n.x || y != n.y {
                apply(.setFrame(id: n.id, x: x, y: y, w: n.w, h: n.h))
            }
        }
    }

    /// Whether the selection is two shapes or more, which booleans combine.
    var combinable: Bool { selection.count > 1 && selected.allSatisfy { $0.kind == .shape } }

    /// Combines the selected shapes into the bottommost by `op`.
    func combine(_ op: BooleanOp) {
        guard combinable else { return }
        select(apply(.boolean(selection, op)))
    }

    /// Layers that follow each other along `axis` without overlapping, and the gaps between them.
    struct Row {
        var axis: XY
        var nodes: [Node]
        var gaps: [Double]
    }

    /// The selected layers as a row, or nil when they are not one or an auto layout places them.
    var row: Row? {
        let nodes = selected
        let parents = Set(nodes.map { self.nodes[$0.id]?.parent?.id ?? "" })
        let parent = nodes.first.flatMap { self.nodes[$0.id]?.parent }
        guard nodes.count >= 2, parents.count == 1, !(parent?.kind == .frame && parent?.direction != Direction.none),
            !nodes.contains(where: { $0.locked || $0.rotation != 0 })
        else { return nil }
        for axis in [XY.x, .y] {
            let s = nodes.sorted { axis == .x ? $0.x < $1.x : $0.y < $1.y }
            let gaps = s.indices.dropFirst().map { i in axis == .x ? s[i].x - s[i - 1].x - s[i - 1].w : s[i].y - s[i - 1].y - s[i - 1].h }
            let beside = s.indices.dropFirst().allSatisfy { i in
                axis == .x ? s[i].y < s[i - 1].y + s[i - 1].h && s[i - 1].y < s[i].y + s[i].h
                    : s[i].x < s[i - 1].x + s[i - 1].w && s[i - 1].x < s[i].x + s[i].w
            }
            if gaps.allSatisfy({ $0 >= 0 }) && beside { return Row(axis: axis, nodes: s, gaps: gaps) }
        }
        return nil
    }

    /// Moves the layers of `row` after its first so that `gap` lies between each and the next.
    func setGap(_ row: Row, _ gap: Double) {
        var at = row.axis == .x ? row.nodes[0].x : row.nodes[0].y
        batch {
            for n in row.nodes {
                if (row.axis == .x ? n.x : n.y) != at {
                    apply(.setFrame(id: n.id, x: row.axis == .x ? at : n.x, y: row.axis == .y ? at : n.y, w: n.w, h: n.h))
                }
                at += (row.axis == .x ? n.w : n.h) + gap
            }
        }
    }
}
