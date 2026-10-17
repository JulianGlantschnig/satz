import AppKit
import SatzCore

/// Layers on the spread: where they show, and what the Edit and Object menus do to them.
extension Editor {
    var selected: [Node] { selection.compactMap { nodes[$0]?.node } }

    /// How far the page of the layer `id` sits right of the spine on its spread.
    func dx(_ id: String) -> Double { nodes[id]?.page?.x ?? 0 }

    /// `n` where it sits on the spread, unturned.
    func placed(_ n: Node) -> Box { Box(x: n.x + dx(n.id), y: n.y, w: n.w, h: n.h) }

    /// The upright box on the spread that `n` and what it does not clip cover.
    func covered(_ n: Node) -> Box {
        let b = n.bounds
        return b.count == 4 ? Box(x: b[0] + dx(n.id), y: b[1], w: b[2], h: b[3]) : placed(n)
    }

    /// The box of `n` as it shows on the spread, turned by its rotation and its ancestors'.
    func shown(_ n: Node) -> Box {
        guard let t = try? engine.turn(n.id), t.count == 6 else { return placed(n) }
        let (a, b, c, d, e, f) = (Double(t[0]), Double(t[1]), Double(t[2]), Double(t[3]), Double(t[4]), Double(t[5]))
        let (cx, cy) = (n.x + n.w / 2, n.y + n.h / 2)
        let x = a * cx + c * cy + e + dx(n.id)
        let y = b * cx + d * cy + f
        return Box(x: x - n.w / 2, y: y - n.h / 2, w: n.w, h: n.h, rotation: atan2(-b, a) * 180 / .pi)
    }

    /// `p` on the spread in the unturned space of the layer `id` on its page.
    func local(_ id: String, _ p: CGPoint) -> CGPoint {
        guard let t = try? engine.turn(id), t.count == 6 else { return CGPoint(x: p.x - dx(id), y: p.y) }
        let (x, y) = (p.x - dx(id) - Double(t[4]), p.y - Double(t[5]))
        return CGPoint(x: Double(t[0]) * x + Double(t[1]) * y, y: Double(t[2]) * x + Double(t[3]) * y)
    }

    /// Start and end in pt of a line, a two-point path, on its page.
    static func ends(_ n: Node) -> (CGPoint, CGPoint)? {
        guard n.kind == .shape, n.shape == .path, let p = n.path, p.count == 6 else { return nil }
        return (CGPoint(x: n.x + p[1] * n.w, y: n.y + p[2] * n.h), CGPoint(x: n.x + p[4] * n.w, y: n.y + p[5] * n.h))
    }

    /// How far the visible stroke of `n` reaches beyond its frame.
    static func outset(_ n: Node) -> Double {
        guard n.kind != .text, n.strokes.contains(where: \.visible) else { return 0 }
        return n.strokeAlign == .outside ? n.strokeWeight : n.strokeAlign == .center ? n.strokeWeight / 2 : 0
    }

    /// Turns `nodes` as they were by `degrees` counterclockwise around `c` on the spread:
    /// a group through its layers, a line by its ends.
    func turn(_ nodes: [Node], by degrees: Double, around c: CGPoint) {
        for n in nodes {
            if n.kind == .group {
                turn(n.children ?? [], by: degrees, around: c)
                continue
            }
            let at = CGPoint(x: c.x - dx(n.id), y: c.y)
            if let (a, b) = Self.ends(n) {
                let (p, q) = (Handles.spin(a, degrees, around: at), Handles.spin(b, degrees, around: at))
                apply(.setPath(id: n.id, path: [0, p.x, p.y, 1, q.x, q.y]))
                continue
            }
            let m = Handles.spin(CGPoint(x: n.x + n.w / 2, y: n.y + n.h / 2), degrees, around: at)
            let rotation = ((n.rotation + degrees).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            apply(.set(id: n.id, ["rotation": .number(rotation)]))
            apply(.setFrame(id: n.id, x: m.x - n.w / 2, y: m.y - n.h / 2, w: n.w, h: n.h))
        }
    }

    /// The page of the spread under `p`, or the nearest.
    func page(at p: CGPoint) -> Page? {
        spread.min { away($0, p) < away($1, p) }
    }

    private func away(_ q: Page, _ p: CGPoint) -> Double { max(q.x - p.x, p.x - q.x - q.width, 0) }

    /// Shows the page or master `id` with nothing selected.
    func showPage(_ id: String) {
        guard id != pageID else { return }
        stopEditing()
        selection = []
        guide = nil
        pageID = id
    }

    /// Makes the page of the selection current when it is all on another page of the spread.
    func settle() {
        let pages = Set(selection.compactMap { nodes[$0]?.page?.id })
        if pages.count == 1, let only = pages.first, only != pageID, snapshot.pages.contains(where: { $0.id == only }) {
            pageID = only
        }
    }

    func select(_ ids: [String]) {
        if let e = editing, !ids.contains(e.id) { stopEditing() }
        selection = ids
        if !ids.isEmpty { guide = nil }
        settle()
    }

    // MARK: Edit menu

    /// The plain text copied layers stand for: the text of text layers, the names of the others.
    func copy() {
        guard !selection.isEmpty else { return }
        apply(.copy(selection))
        var seen = Set<String>()
        let text = selected.compactMap { n -> String? in
            let t = n.kind == .text ? snapshot.stories[n.story ?? ""]?.text ?? "" : n.name
            return seen.insert(t).inserted ? t : nil
        }.joined(separator: "\n")
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        copiedText = text
    }

    func cut() {
        guard !selection.isEmpty else { return }
        batch {
            copy()
            apply(.delete(selection))
        }
    }

    /// Pastes the copied layers above the selection, centred under the pointer when it
    /// is away from where they were; text from elsewhere becomes a text layer, and an
    /// image an image frame.
    func paste() {
        if let image = Self.pastedImage() {
            placeNow(image.data, name: image.name, at: pointer.flatMap { p in sheets.contains { $0.bleedBox.contains(p) } ? p : nil })
            return
        }
        let text = NSPasteboard.general.string(forType: .string)
        if let text, text != copiedText {
            pasteText(text)
            return
        }
        guard let page else { return }
        let ids = batch { () -> [String] in
            let ids = apply(.paste(above: selection, page: page.id))
            let pasted = ids.compactMap { nodes[$0]?.node }
            guard !pasted.isEmpty, let p = pointer else { return ids }
            let b = Box.around(pasted.map(placed))
            guard !b.contains(p) else { return ids }
            let (dx, dy) = (p.x - b.x - b.w / 2, p.y - b.y - b.h / 2)
            for n in pasted { apply(.setFrame(id: n.id, x: n.x + dx, y: n.y + dy, w: n.w, h: n.h)) }
            return ids
        }
        select(ids)
    }

    /// Replaces the text of the one selected text layer with `text`, or places it as a new
    /// text layer amid the current page, at most 80 % of its width wide.
    func pasteText(_ text: String) {
        if selected.count == 1, let one = selected.first, one.kind == .text {
            apply(.setText(id: one.id, text: text))
            return
        }
        guard let page else { return }
        let id = batch { () -> String? in
            guard let id = apply(.create(parent: page.id, kind: .text, x: 0, y: 0, w: 0, h: 0)).first else { return nil }
            apply(.set(id: id, Self.insets))
            apply(.setText(id: id, text: text))
            if let m = nodes[id]?.node, m.w > page.width * 0.8 { apply(.setFrame(id: id, x: 0, y: 0, w: page.width * 0.8, h: m.h)) }
            if let m = nodes[id]?.node { apply(.setFrame(id: id, x: (page.width - m.w) / 2, y: (page.height - m.h) / 2, w: m.w, h: m.h)) }
            return id
        }
        if let id { select([id]) }
    }

    /// The insets of a new text frame: 1 mm all round.
    static let insets: [String: JSON] = [
        "insetTop": .number(Units.mm(1)), "insetRight": .number(Units.mm(1)),
        "insetBottom": .number(Units.mm(1)), "insetLeft": .number(Units.mm(1)),
    ]

    /// Duplicates `ids` and selects the copies. Duplicating the last copies again after
    /// they were moved moves the new copies as far on, unless `step` is false.
    func duplicate(_ ids: [String], step: Bool = true) {
        guard let first = ids.first, let at = nodes[first]?.node else { return }
        let last = step && copies?.ids == ids ? copies?.from : nil
        let d = last.map { CGPoint(x: at.x - $0.x, y: at.y - $0.y) } ?? .zero
        let made = batch { () -> [String] in
            let made = apply(.duplicate(ids))
            if d != .zero {
                for id in made {
                    guard let n = nodes[id]?.node else { continue }
                    apply(.setFrame(id: id, x: n.x + d.x, y: n.y + d.y, w: n.w, h: n.h))
                }
            }
            return made
        }
        copies = (made, CGPoint(x: at.x, y: at.y))
        select(made)
    }

    func delete() {
        if let g = guide, let page = snapshot.page(g.page) {
            var guides = page.guides
            if g.axis == .x { guides.x.remove(at: g.index) } else { guides.y.remove(at: g.index) }
            if let cmd = try? Command.setGuides(page.id, guides) { apply(cmd) }
            guide = nil
            return
        }
        guard !selection.isEmpty else { return }
        apply(.delete(selection))
    }

    /// Selects the layers beside the selected one, or those of the page.
    func selectAll() {
        let siblings = selection.first.flatMap { nodes[$0]?.parent?.children } ?? page?.children ?? []
        select(siblings.map(\.id))
    }

    // MARK: Object menu

    func group(frame: Bool = false) {
        guard !selection.isEmpty else { return }
        select(apply(.group(selection, frame: frame)))
    }

    func ungroup() {
        guard !selection.isEmpty else { return }
        select(apply(.ungroup(selection)))
    }

    func order(_ to: Order) {
        guard !selection.isEmpty else { return }
        apply(.order(selection, to: to))
    }

    /// Hides or shows, locks or unlocks the selection: on unless all have it.
    func toggle(_ prop: String) {
        let on = selected.contains { prop == "hidden" ? !$0.hidden : !$0.locked }
        batch {
            for n in selected { apply(.set(id: n.id, [prop: .bool(on)])) }
        }
    }

    func flip(vertical: Bool) {
        batch {
            for id in selection { apply(.flip(id, vertical: vertical)) }
        }
    }

    func mask() {
        guard !selection.isEmpty else { return }
        select(apply(.mask(selection)))
    }

    /// Moves the selection by (dx, dy) mm.
    func nudge(dx: Double, dy: Double) {
        batch {
            for n in selected {
                apply(.setFrame(id: n.id, x: n.x + Units.mm(dx), y: n.y + Units.mm(dy), w: n.w, h: n.h))
            }
        }
    }

    /// Escape: leaves the selection for its parent, or the master for its page.
    func escape() {
        if let first = selection.first, let parent = nodes[first]?.parent {
            select([parent.id])
        } else if !selection.isEmpty || guide != nil {
            selection = []
            guide = nil
        } else if master != nil, let back = snapshot.pages.first {
            showPage(back.id)
        }
    }

    /// Enter: selects the children of the selected groups and frames.
    func enter() {
        let kids = selected.flatMap { $0.children?.map(\.id) ?? [] }
        if !kids.isEmpty { select(kids) }
    }

    /// Shift-Enter: selects the parent of the selection when it shares one.
    func selectParent() {
        guard let first = selection.first, let parent = nodes[first]?.parent,
            selection.allSatisfy({ nodes[$0]?.parent?.id == parent.id })
        else { return }
        select([parent.id])
    }

    /// Tab and Shift-Tab: the next or previous layer beside the selected one.
    func selectNext(backwards: Bool) {
        let siblings = (selection.first.flatMap { nodes[$0]?.parent?.children } ?? page?.children ?? []).reversed().map(\.id)
        guard !siblings.isEmpty else { return }
        let i = selection.first.flatMap { siblings.firstIndex(of: $0) } ?? -1
        let n = siblings.count
        select([siblings[((i + (backwards ? -1 : 1)) % n + n) % n]])
    }
}
