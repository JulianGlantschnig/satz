import Foundation

/// A layer, the layer it is in, and the page it is on.
public struct Entry: Sendable {
    public var node: Node
    public var parent: Node?
    public var page: Page?
}

public enum Select {
    public enum Mode: Sendable { case click, double, deep }

    /// The layers of `nodes` and below by id; see `web/src/select.ts`.
    public static func index(_ nodes: [Node], parent: Node? = nil, page: Page? = nil, into out: inout [String: Entry]) {
        for node in nodes {
            out[node.id] = Entry(node: node, parent: parent, page: page)
            if let children = node.children { index(children, parent: node, page: page, into: &out) }
        }
    }

    public static func index(_ nodes: [Node], page: Page? = nil) -> [String: Entry] {
        var out: [String: Entry] = [:]
        index(nodes, page: page, into: &out)
        return out
    }

    /// The layer of the hit `path` (outermost first) that a click picks: the outermost
    /// group, passing through frames, unless the selection is deeper; a double click
    /// enters the selected group; a deep click takes the deepest layer.
    public static func pick(_ nodes: [Node], path: [String], selection: [String], mode: Mode) -> String? {
        if mode == .deep { return path.last }
        if mode == .double, let i = path.firstIndex(where: { selection.contains($0) }) {
            return path[min(i + 1, path.count - 1)]
        }
        guard !path.isEmpty else { return nil }
        let all = index(nodes)
        let parents = Set(selection.compactMap { all[$0]?.parent?.id })
        var i = path.count - 1
        while i > 0 {
            if parents.contains(path[i - 1]) { return path[i] }
            i -= 1
        }
        i = 0
        while i < path.count - 1 && all[path[i]]?.node.kind == .frame { i += 1 }
        return path[i]
    }

    /// `selection` after a shift click on `id` of `list`: before or after the selected
    /// ones of `list` it adds those up to `id`, among them it drops those after `id`.
    /// Nil when `selection` holds none of `list`.
    public static func span(_ list: [String], selection: [String], id: String) -> [String]? {
        let at = selection.compactMap { list.firstIndex(of: $0) }
        guard let c = list.firstIndex(of: id), let a = at.min(), let b = at.max() else { return nil }
        let range = c < a ? Array(list[c..<a]) : c > b ? Array(list[(b + 1)...c]) : []
        let kept = selection.filter { s in s != id && (c < a || (list.firstIndex(of: s).map { $0 <= c } ?? true)) }
        return kept + range.filter { $0 != id } + [id]
    }
}
