import AppKit
import SatzCore

/// What a drag on the canvas does.
enum Drag {
    case pan(last: CGPoint)
    case move(start: CGPoint, frames: [Node], active: Bool, box: Box?, snaps: Snaps?)
    case resize(start: CGPoint, handle: String, box: Box, frames: [Node], snaps: Snaps, by: Double, turn: Double, own: Double)
    case rotate(center: CGPoint, from: Double, nodes: [Node], handle: String, turn: Double)
    case end(start: CGPoint, id: String, ends: (CGPoint, CGPoint), index: Int)
    case radius(start: CGPoint, id: String, box: Box, radii: [Double], index: Int, turn: Double)
    case marquee(start: CGPoint, end: CGPoint, base: [String])
    case guide(axis: XY, page: String, dx: Double, index: Int, grouped: Bool)
    /// Draws a new layer with `tool`; it is made once the press moves or ends on a page.
    case draw(start: CGPoint, id: String?, dx: Double, moved: Bool, tool: Editor.Tool, snaps: Snaps)
    /// Selects in the edited text, by characters, words or paragraphs.
    case text(unit: Int)
}

/// What a drag snaps to and the layers it measures to.
struct Snaps {
    var lines: SnapLines
    var others: [Box]
}

/// What the canvas shows over the pages while the pointer works.
struct Overlay {
    var hover: String?
    var snapped: [SnapGuide] = []
    var measures: [Measure] = []
    /// The size of what is being resized, under it.
    var size: Box?
    /// The angle of what is being turned, beside the pointer.
    var turn: Double?
    var pointer: CGPoint?
}

extension CanvasView {
    /// Distance in canvas points within which outlines are hit and layers snap.
    static let hitSlop: Double = 6
    static let snapSlop: Double = 5
    /// Distance a press moves before it drags.
    static let dragSlop: Double = 3

    // MARK: Geometry

    func toSpread(_ event: NSEvent) -> CGPoint { view.toSpread(convert(event.locationInWindow, from: nil)) }

    /// The path of layers at `p`, outermost first, on the topmost page of the spread that has one there.
    func hit(_ p: CGPoint) -> (page: Page?, path: [String]) {
        if let m = editor.master {
            return (m, editor.engine.hit(page: m.id, at: CGPoint(x: p.x - m.x, y: p.y), tolerance: Self.hitSlop / view.zoom))
        }
        for page in editor.spread.reversed() {
            let path = editor.engine.hit(page: page.id, at: CGPoint(x: p.x - page.x, y: p.y), tolerance: Self.hitSlop / view.zoom)
            if !path.isEmpty { return (page, path) }
        }
        return (editor.page(at: p), [])
    }

    /// The layer that a click at `p` picks.
    func pick(_ p: CGPoint, _ mode: Select.Mode) -> String? {
        let (page, path) = hit(p)
        guard let page else { return nil }
        return Select.pick(page.children, path: path, selection: editor.selection, mode: mode)
    }

    /// The turn of `nodes` as shown and their own, when they are one layer or all turn
    /// alike on unturned parents.
    func turnOf(_ nodes: [Node]) -> (shown: Double, own: Double) {
        let turns = nodes.map { editor.shown($0).rotation }
        guard let first = turns.first else { return (0, 0) }
        let near = { (a: Double) in abs(a - first) < 1e-6 }
        if nodes.count == 1 || zip(nodes, turns).allSatisfy({ near($1) && near($0.rotation) }) {
            return (first, nodes[0].rotation)
        }
        return (0, 0)
    }

    /// `b` with its centre turned by `by` degrees about the origin.
    static func spun(_ b: Box, _ by: Double) -> Box {
        let c = Handles.spin(b.center, by)
        return Box(x: c.x - b.w / 2, y: c.y - b.h / 2, w: b.w, h: b.h, rotation: b.rotation)
    }

    /// The selection box of `nodes`, turned with them.
    func boxOf(_ nodes: [Node]) -> Box {
        if nodes.count == 1 { return editor.shown(nodes[0]) }
        let (turn, own) = turnOf(nodes)
        var b = Self.spun(Box.around(nodes.map { Self.spun(editor.placed($0), -own) }), own)
        b.rotation = turn
        return b
    }

    struct Selection {
        var box: Box?
        var line: (CGPoint, CGPoint)?
        var radii: [CGPoint] = []
    }

    /// The handles of the selection: a box, or the ends of a single selected line.
    func selectionHandles() -> Selection {
        let nodes = editor.selected
        guard !nodes.isEmpty, editor.editing == nil else { return Selection() }
        if nodes.count == 1, let (a, b) = Editor.ends(nodes[0]) {
            let dx = editor.dx(nodes[0].id)
            return Selection(line: (CGPoint(x: a.x + dx, y: a.y), CGPoint(x: b.x + dx, y: b.y)))
        }
        if nodes.count == 1 {
            let n = nodes[0]
            let shown = editor.shown(n)
            let radii = n.isRounded && !isDrawing ? Handles.radiusHandles(view, shown, radii: n.radii) : []
            return Selection(box: shown.grown(by: Editor.outset(n)), radii: radii)
        }
        let box = turnOf(nodes).shown != 0 ? boxOf(nodes) : Box.around(nodes.map { editor.placed($0).grown(by: Editor.outset($0)) })
        return Selection(box: box)
    }

    private var isDrawing: Bool { false }

    func handle(at q: CGPoint) -> Handle? {
        let s = selectionHandles()
        return Handles.at(view, q, box: s.box, line: s.line, radii: s.radii)
    }

    /// What the layers `ids` snap to: the pages of the spread and the visible layers beside them.
    func snaps(ids: [String]? = nil, sheets: [Sheet]? = nil) -> Snaps {
        let ids = ids ?? editor.selection
        func top(_ id: String) -> String? {
            var e = editor.nodes[id]
            while let p = e?.parent { e = editor.nodes[p.id] }
            return e?.node.id
        }
        let skip = Set(ids + ids.compactMap(top))
        let siblings = ids.flatMap { editor.nodes[$0]?.parent?.children ?? [] }
        let tops = (editor.master.map { [$0] } ?? editor.spread).flatMap(\.children)
        var seen = Set<String>()
        let others = (tops + siblings).filter { !$0.hidden && !skip.contains($0.id) && seen.insert($0.id).inserted }
        let targets = others.map { SnapTarget(box: editor.covered($0), text: $0.kind == .text ? $0 : nil) }
        return Snaps(lines: Snap.targets(sheets ?? editor.sheets, targets, grids: editor.showsGrids), others: targets.map(\.box))
    }

    /// The guide within reach of `p`.
    func guide(at p: CGPoint) -> (axis: XY, page: String, dx: Double, index: Int)? {
        guard editor.showsGrids else { return nil }
        for s in editor.sheets {
            if let i = s.guides.x.firstIndex(where: { abs(s.x + $0 - p.x) < Self.hitSlop / view.zoom }) { return (.x, s.id, s.x, i) }
            if let i = s.guides.y.firstIndex(where: { abs($0 - p.y) < Self.hitSlop / view.zoom }) { return (.y, s.id, s.x, i) }
        }
        return nil
    }

    /// Degrees counterclockwise of `p` around `c`.
    static func angle(_ c: CGPoint, _ p: CGPoint) -> Double { atan2(c.y - p.y, p.x - c.x) * 180 / .pi }

    /// A vector snapped to the nearest multiple of 45°.
    static func snap45(_ dx: CGFloat, _ dy: CGFloat) -> (CGFloat, CGFloat) {
        let (x, y) = snap45(Double(dx), Double(dy))
        return (CGFloat(x), CGFloat(y))
    }

    static func snap45(_ dx: Double, _ dy: Double) -> (Double, Double) {
        let a = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let d = hypot(dx, dy)
        return (cos(a) * d, sin(a) * d)
    }

    // MARK: Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
            owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        track(event)
    }

    override func mouseExited(with event: NSEvent) {
        overlay.pointer = nil
        overlay.hover = nil
        editor.pointer = nil
        if editor.pointerInk != nil { editor.pointerInk = nil }
        needsDisplay = true
    }

    /// Follows the pointer: what it is over and the cursor for it.
    func track(_ event: NSEvent) {
        let q = convert(event.locationInWindow, from: nil)
        let p = view.toSpread(q)
        overlay.pointer = q
        editor.pointer = p
        if editor.showsPreflight {
            let ink = inkCoverage(at: p)
            if ink != editor.pointerInk { editor.pointerInk = ink }
        }
        guard drag == nil else { return }
        if let from = editor.threading {
            let to = textUnder(p)
            (to != nil && to != from && !editor.engine.canThread(from: from, to: to!) ? NSCursor.operationNotAllowed : NSCursor.dragLink).set()
            overlay.hover = to
            needsDisplay = true
            return
        }
        guard editor.tool == .move else {
            overlay.hover = nil
            (editor.tool == .text ? NSCursor.iBeam : NSCursor.crosshair).set()
            return
        }
        if port(at: q) != nil {
            NSCursor.pointingHand.set()
            return
        }
        if inEdited(p) != nil {
            overlay.hover = nil
            NSCursor.iBeam.set()
            return
        }
        let deep = event.modifierFlags.contains(.command)
        let hover = pick(p, deep ? .deep : .click)
        if hover != overlay.hover {
            overlay.hover = hover
            needsDisplay = true
        }
        cursor(for: handle(at: q), guide: guide(at: p)).set()
    }

    func cursor(for handle: Handle?, guide: (axis: XY, page: String, dx: Double, index: Int)?) -> NSCursor {
        if spaceHeld { return .openHand }
        if editor.tool != .move { return .crosshair }
        if let guide { return guide.axis == .x ? .resizeLeftRight : .resizeUpDown }
        let turn = selectionHandles().box?.rotation ?? 0
        switch handle {
        case .resize(let h)?:
            return Self.resizeCursor(h, turn: turn)
        case .rotate?:
            return .crosshair
        case .end?, .radius?:
            return .crosshair
        case .gap(let axis, _)?:
            return axis == .x ? .resizeLeftRight : .resizeUpDown
        case nil:
            return .arrow
        }
    }

    /// The resize cursor of the handle `h` of a box turned `turn` degrees counterclockwise.
    static func resizeCursor(_ h: String, turn: Double) -> NSCursor {
        let degrees: [String: Double] = ["e": 0, "ne": 45, "n": 90, "nw": 135, "w": 180, "sw": 225, "s": 270, "se": 315]
        let a = (((degrees[h] ?? 0) + turn).truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
        switch Int((a / 45).rounded()) % 4 {
        case 0: return .frameResize(position: .right, directions: .all)
        case 1: return .frameResize(position: .topRight, directions: .all)
        case 2: return .frameResize(position: .top, directions: .all)
        default: return .frameResize(position: .topLeft, directions: .all)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let q = convert(event.locationInWindow, from: nil)
        let p = view.toSpread(q)
        let flags = event.modifierFlags
        if spaceHeld {
            drag = .pan(last: q)
            NSCursor.closedHand.set()
            return
        }
        if let frame = inEdited(p) {
            let i = textIndex(frame.id, at: p)
            let text = editor.editedText
            switch event.clickCount {
            case 2:
                let w = TextEdit.word(at: i, in: text)
                editor.selectText(w.lowerBound, w.upperBound)
            case 3...:
                let r = TextEdit.paragraph(at: i, in: text)
                editor.selectText(r.lowerBound, r.upperBound)
            default:
                editor.selectText(flags.contains(.shift) ? editor.editing?.anchor ?? i : i, i)
            }
            drag = .text(unit: min(event.clickCount, 3))
            wakeCaret()
            return
        }
        editor.stopEditing()
        if event.clickCount == 2 {
            if let hit = port(at: q) {
                // Double-clicking a port breaks the thread there.
                let id = hit.side == .out ? hit.node.id : hit.node.prev
                if let id, hit.side == .in || hit.node.next != nil { editor.apply(.unthread(id)) }
                editor.threading = nil
                return
            }
            doubleClick(p)
            return
        }
        if let g = guide(at: p) {
            editor.select([])
            editor.guide = Editor.PickedGuide(page: g.page, axis: g.axis, index: g.index)
            drag = .guide(axis: g.axis, page: g.page, dx: g.dx, index: g.index, grouped: false)
            return
        }
        editor.guide = nil
        if let from = editor.threading {
            if port(at: q) != nil { return }
            let to = textUnder(p)
            if to == from { return }
            if let to {
                editor.thread(from: from, to: to)
                return
            }
            // A new frame drawn or clicked beside the others continues the thread.
            let s = snaps()
            drag = makeDrawn(.draw(start: p, id: nil, dx: 0, moved: false, tool: .text, snaps: s))
            return
        }
        if event.clickCount == 1, let hit = port(at: q) {
            if hit.side == .out { editor.threading = hit.node.id }
            return
        }
        if editor.tool == .eyedropper {
            // Takes the fills and strokes of the layer clicked onto the selection.
            guard let id = hit(p).path.last, let from = editor.nodes[id]?.node else { return }
            editor.batch {
                for n in editor.selected where n.kind != .group && n.id != from.id {
                    editor.apply(.set(id: n.id, [
                        "fills": (try? JSON(encoding: from.fills)) ?? .null,
                        "strokes": (try? JSON(encoding: from.strokes)) ?? .null,
                        "strokeWeight": .number(from.strokeWeight),
                    ]))
                }
            }
            return
        }
        if editor.tool != .move {
            let s = snaps()
            let at = snapPoint(p, s, off: flags.contains(.command)).p
            var d = Drag.draw(start: at, id: nil, dx: 0, moved: false, tool: editor.tool, snaps: s)
            if editor.sheets.contains(where: { $0.bleedBox.contains(at) }) { d = makeDrawn(d) }
            drag = d
            return
        }
        let h = handle(at: q)
        switch h {
        case .end(let i)?:
            if let n = editor.selected.first, let (a, b) = Editor.ends(n) {
                let dx = editor.dx(n.id)
                drag = .end(start: p, id: n.id, ends: (CGPoint(x: a.x + dx, y: a.y), CGPoint(x: b.x + dx, y: b.y)), index: i)
                editor.beginGroup()
            }
            return
        case .radius(let i)?:
            if let n = editor.selected.first, n.isRounded {
                drag = .radius(start: p, id: n.id, box: editor.placed(n), radii: n.radii, index: i, turn: editor.shown(n).rotation)
                editor.beginGroup()
            }
            return
        case .rotate(let handle)?:
            let nodes = editor.selected
            let b = boxOf(nodes)
            drag = .rotate(center: b.center, from: Self.angle(b.center, p), nodes: nodes, handle: handle, turn: b.rotation)
            editor.beginGroup()
            return
        case .resize(let handle)?:
            let frames = editor.selected
            let (turn, own) = turnOf(frames)
            let box = Box.around(frames.map { Self.spun(editor.placed($0), -own) })
            drag = .resize(start: p, handle: handle, box: box, frames: frames, snaps: snaps(), by: 1, turn: turn, own: own)
            editor.beginGroup()
            return
        case .gap?, nil:
            break
        }
        // Command-Shift-click on a master layer that no page layer covers overrides it, as in InDesign.
        if flags.contains(.command), flags.contains(.shift), editor.master == nil, hit(p).path.isEmpty,
            let page = editor.page(at: p),
            let id = editor.engine.masterHit(page: page.id, at: CGPoint(x: p.x - page.x, y: p.y), tolerance: Self.hitSlop / view.zoom)
        {
            editor.override(id, on: page.id)
            return
        }
        let sel = editor.selection
        guard let id = pick(p, flags.contains(.command) ? .deep : .click) else {
            let base = flags.contains(.shift) ? sel : []
            drag = .marquee(start: p, end: p, base: base)
            editor.select(base)
            return
        }
        if flags.contains(.shift) {
            editor.select(sel.contains(id) ? sel.filter { $0 != id } : sel + [id])
            return
        }
        if !sel.contains(id) { editor.select([id]) }
        drag = .move(start: p, frames: editor.selected, active: false, box: nil, snaps: nil)
    }

    override func otherMouseDown(with event: NSEvent) {
        drag = .pan(last: convert(event.locationInWindow, from: nil))
        NSCursor.closedHand.set()
    }

    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { mouseUp(with: event) }

    override func mouseDragged(with event: NSEvent) {
        if event.type != .otherMouseDragged { autoscroll(for: event) }
        dragged(event)
    }

    /// Follows a drag to the pointer of `event`.
    func dragged(_ event: NSEvent) {
        let q = convert(event.locationInWindow, from: nil)
        let p = view.toSpread(q)
        overlay.pointer = q
        editor.pointer = p
        let flags = event.modifierFlags
        let free = !flags.contains(.command)
        let tolerance = Self.snapSlop / view.zoom
        guard let drag else { return }
        switch drag {
        case .pan(let last):
            show(Viewport(x: view.x + q.x - last.x, y: view.y + q.y - last.y, zoom: view.zoom))
            self.drag = .pan(last: q)

        case .marquee(let start, _, let base):
            self.drag = .marquee(start: start, end: p, base: base)
            let m = Handles.rect(start, p)
            let pages = editor.master.map { [$0] } ?? editor.spread
            let inside = pages.flatMap { page in
                page.children.filter { n in
                    let x = n.x + page.x
                    return !n.hidden && !n.locked && x < m.x + m.w && x + n.w > m.x && n.y < m.y + m.h && n.y + n.h > m.y
                }.map(\.id)
            }
            var seen = Set<String>()
            editor.select((base + inside).filter { seen.insert($0).inserted })

        case .move(let start, var frames, var active, var box, var snapsNow):
            var dx = p.x - start.x
            var dy = p.y - start.y
            if !active {
                guard hypot(dx, dy) * view.zoom > Self.dragSlop else { return }
                active = true
                editor.beginGroup()
                if flags.contains(.option) {
                    editor.duplicate(frames.map(\.id), step: false)
                    frames = editor.selected
                }
                box = Box.around(frames.map(editor.covered))
                snapsNow = snaps()
            }
            guard let b = box, let s = snapsNow else { return }
            let lock: XY? = flags.contains(.shift) ? (abs(dx) > abs(dy) ? .y : .x) : nil
            if lock == .y { dy = 0 }
            if lock == .x { dx = 0 }
            func xs(_ d: Double) -> [Double] { lock == .x ? [] : [b.x + d, b.x + d + b.w / 2, b.x + d + b.w] }
            func ys(_ d: Double) -> [Double] { lock == .y ? [] : [b.y + d, b.y + d + b.h / 2, b.y + d + b.h] }
            if free {
                func by(_ axis: XY, _ values: [Double]) -> Double {
                    let line = Snap.snap(values, axis == .x ? s.lines.x : s.lines.y, tolerance: tolerance)
                    guard let first = values.first else { return line }
                    let moved = Box(x: b.x + dx, y: b.y + dy, w: b.w, h: b.h)
                    let gaps = Snap.spacings(moved, s.others, axis: axis).map { SnapLine(at: $0, from: 0, to: 0) }
                    let gap = Snap.snap([first], gaps, tolerance: tolerance)
                    return gap != 0 && (line == 0 || abs(gap) < abs(line)) ? gap : line
                }
                dx += by(.x, xs(dx))
                dy += by(.y, ys(dy))
            }
            let moved = Box(x: b.x + dx, y: b.y + dy, w: b.w, h: b.h)
            overlay.snapped = free ? Snap.guides(moved, s.lines, xs: xs(dx), ys: ys(dy)) : []
            let all = Snap.nearest(moved, s.others).flatMap { Snap.measure(moved, $0) }
                + Snap.equals(moved, s.others, axis: .x) + Snap.equals(moved, s.others, axis: .y)
            var seen = Set<String>()
            overlay.measures = all.filter { seen.insert("\($0.x1) \($0.y1) \($0.x2) \($0.y2)").inserted }
            for n in frames { editor.apply(.setFrame(id: n.id, x: n.x + dx, y: n.y + dy, w: n.w, h: n.h)) }
            self.drag = .move(start: start, frames: frames, active: active, box: box, snaps: snapsNow)

        case .resize(let start, let h, let b, let frames, let s, let by, let turn, let own):
            var d = Handles.spin(CGPoint(x: p.x - start.x, y: p.y - start.y), -turn)
            func edge(_ side: Character, _ at: Double) -> [Double] { h.contains(side) ? [at] : [] }
            if turn == 0 && free {
                d.x += Snap.snap(edge("w", b.x + d.x) + edge("e", b.x + b.w + d.x), s.lines.x, tolerance: tolerance)
                d.y += Snap.snap(edge("n", b.y + d.y) + edge("s", b.y + b.h + d.y), s.lines.y, tolerance: tolerance)
            }
            let keep = flags.contains(.shift) || frames.contains { $0.keepRatio }
            let turned = Handles.resized(b, handle: h, by: d, alt: flags.contains(.option), shift: keep, frames: frames.map { Self.spun(editor.placed($0), -own) })
            let boxes = turned.map { Self.spun($0, own) }
            let r = Box.around(turned)
            overlay.snapped = turn == 0 && free ? Snap.guides(r, s.lines, xs: edge("w", r.x) + edge("e", r.x + r.w), ys: edge("n", r.y) + edge("s", r.y + r.h)) : []
            overlay.size = r
            // Command scales the text of text frames with them.
            let ratio = h == "e" || h == "w" ? r.w / max(b.w, 1e-9) : r.h / max(b.h, 1e-9)
            let scale = flags.contains(.command) && ratio > 0 ? ratio / by : 1
            for (n, f) in zip(frames, boxes) {
                if scale != 1 && n.kind == .text { editor.apply(.scaleText(n.id, by: scale)) }
                editor.apply(.setFrame(id: n.id, x: f.x - editor.dx(n.id), y: f.y, w: f.w, h: f.h, crop: flags.contains(.command)))
                if (h == "e" || h == "w"), let t = editor.nodes[n.id]?.node, t.kind == .text, t.overset == true, t.next == nil, t.sizing.vertical == .fixed {
                    var sizing = t.sizing
                    sizing.vertical = .hug
                    if let json = try? JSON(encoding: sizing) { editor.apply(.set(id: n.id, ["sizing": json])) }
                }
            }
            self.drag = .resize(start: start, handle: h, box: b, frames: frames, snaps: s, by: by * scale, turn: turn, own: own)

        case .rotate(let c, let from, let nodes, _, _):
            var by = Self.angle(c, p) - from
            if flags.contains(.shift) { by = (by / 15).rounded() * 15 }
            // Each move turns the layers as they were when the drag began.
            editor.turn(nodes, by: by, around: c)
            overlay.turn = by

        case .end(let start, let id, let ends, let index):
            let fixed = index == 0 ? ends.1 : ends.0
            let from = index == 0 ? ends.0 : ends.1
            var dx = Double(from.x + p.x - start.x - fixed.x)
            var dy = Double(from.y + p.y - start.y - fixed.y)
            if flags.contains(.shift) { (dx, dy) = Self.snap45(dx, dy) }
            let moved = CGPoint(x: fixed.x + dx, y: fixed.y + dy)
            let (a, b) = index == 1 ? (fixed, moved) : (moved, fixed)
            let off = editor.dx(id)
            editor.apply(.setPath(id: id, path: [0, a.x - off, a.y, 1, b.x - off, b.y]))

        case .radius(let start, let id, let b, let radii, let i, let turn):
            let (sx, sy): (Double, Double) = (i == 1 || i == 2 ? -1 : 1, i < 2 ? 1 : -1)
            let d = Handles.spin(CGPoint(x: p.x - start.x, y: p.y - start.y), -turn)
            let r = max(0, min(radii[i] + (d.x * sx + d.y * sy) / 2, b.w / 2, b.h / 2))
            if flags.contains(.command) {
                let corners = radii.enumerated().map { $0.offset == i ? r : $0.element }
                editor.apply(.set(id: id, ["corners": .array(corners.map { .number($0) })]))
            } else {
                editor.apply(.set(id: id, ["radius": .number(r), "corners": .array([])]))
            }

        case .text(let unit):
            guard let e = editor.editing else { return }
            let id = inEdited(p)?.id ?? e.id
            let i = textIndex(id, at: p)
            if unit == 1 {
                editor.selectText(e.anchor, i)
            } else {
                let text = editor.editedText
                let w = unit == 2 ? TextEdit.word(at: i, in: text) : TextEdit.paragraph(at: i, in: text)
                editor.selectText(min(e.range.lowerBound, w.lowerBound), max(e.range.upperBound, w.upperBound))
            }

        case .draw(let start, let made, let pdx, var moved, let tool, let s):
            moved = moved || hypot(p.x - start.x, p.y - start.y) * view.zoom > Self.dragSlop
            guard moved else { return }
            var d = Drag.draw(start: start, id: made, dx: pdx, moved: moved, tool: tool, snaps: s)
            if made == nil { d = makeDrawn(d) }
            guard case .draw(_, let id?, let dx0, _, _, _) = d else { self.drag = d; return }
            let snapped = snapPoint(p, s, off: !free || flags.contains(.shift))
            overlay.snapped = snapped.guides
            var dx = snapped.p.x - start.x
            var dy = snapped.p.y - start.y
            if tool == .line {
                if flags.contains(.shift) { (dx, dy) = Self.snap45(dx, dy) }
                let (x, y) = (start.x - dx0, start.y)
                editor.apply(.setPath(id: id, path: [0, x, y, 1, x + dx, y + dy]))
            } else {
                if flags.contains(.shift) {
                    let m = max(abs(dx), abs(dy))
                    dx = (dx < 0 ? -1 : 1) * m
                    dy = (dy < 0 ? -1 : 1) * m
                }
                let a = flags.contains(.option) ? CGPoint(x: start.x - dx, y: start.y - dy) : start
                let r = Handles.rect(a, CGPoint(x: start.x + dx, y: start.y + dy))
                overlay.size = r
                editor.apply(.setFrame(id: id, x: r.x - dx0, y: r.y, w: r.w, h: r.h))
            }
            self.drag = d

        case .guide(let axis, var pageID, var dx, var index, var grouped):
            let off = axis == .x ? q.y < 0 : q.x < 0
            if index < 0 && off { return }
            if index < 0, let page = editor.page(at: p) ?? editor.master {
                pageID = page.id
                dx = editor.sheets.first { $0.id == page.id }?.x ?? page.x
            }
            guard let sheet = editor.sheets.first(where: { $0.id == pageID }) else { return }
            if !grouped { editor.beginGroup() }
            grouped = true
            var had = sheet.guides
            var rest = axis == .x ? had.x : had.y
            if index >= 0 && index < rest.count { rest.remove(at: index) }
            let sheets = editor.sheets.map { s -> Sheet in
                var s = s
                if s.id == pageID { if axis == .x { s.guides.x = rest } else { s.guides.y = rest } }
                return s
            }
            let s = snaps(ids: [], sheets: sheets)
            let v = axis == .x ? p.x : p.y
            let at = v + (free ? Snap.snap([v], axis == .x ? s.lines.x : s.lines.y, tolerance: tolerance) : 0)
            let line = axis == .x ? Box(x: at, y: 0, w: 0, h: sheet.height) : Box(x: sheet.x, y: at, w: sheet.width, h: 0)
            overlay.snapped = free && !off ? Snap.guides(line, s.lines, xs: axis == .x ? [at] : [], ys: axis == .y ? [at] : []) : []
            let placed = off ? rest : rest + [axis == .x ? at - dx : at]
            if axis == .x { had.x = placed } else { had.y = placed }
            if let cmd = try? Command.setGuides(pageID, had) { editor.apply(cmd) }
            index = off ? -1 : rest.count
            editor.guide = off ? nil : Editor.PickedGuide(page: pageID, axis: axis, index: index)
            self.drag = .guide(axis: axis, page: pageID, dx: dx, index: index, grouped: grouped)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = toSpread(event)
        defer {
            drag = nil
            overlay.snapped = []
            overlay.measures = []
            overlay.size = nil
            overlay.turn = nil
            needsDisplay = true
            track(event)
        }
        guard let drag else { return }
        switch drag {
        case .move(_, let frames, let active, _, _) where active:
            // A layer dragged across the spine goes to the page its centre is on.
            var moves: [String: [String]] = [:]
            for n in frames {
                guard let entry = editor.nodes[n.id], entry.parent == nil, let node = editor.nodes[n.id]?.node else { continue }
                let c = editor.placed(node).center
                if let to = editor.page(at: c), to.id != entry.page?.id { moves[to.id, default: []].append(n.id) }
            }
            for (to, ids) in moves {
                let count = editor.snapshot.page(to)?.children.count ?? 0
                editor.apply(.move(ids, parent: to, index: count))
            }
            editor.endGroup()
        case .move(_, _, _, _, _):
            if !event.modifierFlags.contains(.shift), editor.selection.count > 1,
                let id = pick(p, event.modifierFlags.contains(.command) ? .deep : .click)
            {
                editor.select([id])
            }
        case .resize, .end, .radius, .rotate:
            editor.endGroup()
        case .guide(_, _, _, _, let grouped) where grouped:
            editor.endGroup()
        case .draw(let start, let id?, let dx, let moved, _, _) where editor.threading != nil:
            let from = editor.threading!
            if !moved, let f = editor.nodes[from]?.node ?? editor.selected.first {
                editor.apply(.setFrame(id: id, x: start.x - dx, y: start.y, w: f.w, h: f.h))
            }
            editor.endGroup()
            if editor.engine.canThread(from: from, to: id) {
                editor.thread(from: from, to: id)
            } else {
                editor.apply(.delete([id]))
                editor.threading = nil
                editor.select([])
            }
        case .draw(let start, let id?, let dx, let moved, let tool, _):
            if !moved && tool != .text {
                let (w, h) = tool.size
                editor.apply(.setFrame(id: id, x: start.x - dx, y: start.y, w: Units.mm(w), h: Units.mm(h)))
            }
            editor.endGroup()
            editor.tool = .move
            if tool == .text {
                editor.edit(id)
                wakeCaret()
            }
        case .draw(_, nil, _, _, _, _):
            editor.tool = .move
            editor.select([])
        default:
            break
        }
    }

    /// `p` moved onto what it snaps to, unless `off`, with the guides through it.
    func snapPoint(_ p: CGPoint, _ s: Snaps?, off: Bool) -> (p: CGPoint, guides: [SnapGuide]) {
        guard let s, !off else { return (p, []) }
        let tolerance = Self.snapSlop / view.zoom
        let q = CGPoint(x: p.x + Snap.snap([p.x], s.lines.x, tolerance: tolerance), y: p.y + Snap.snap([p.y], s.lines.y, tolerance: tolerance))
        return (q, Snap.guides(Box(x: q.x, y: q.y, w: 0, h: 0), s.lines, xs: [q.x], ys: [q.y]))
    }

    /// The frame or page under `p` that a new layer goes into, and how far its page sits right of the spine.
    func parent(at p: CGPoint) -> (id: String, dx: Double)? {
        let h = hit(p)
        if let frame = h.path.last(where: { editor.nodes[$0]?.node.kind == .frame }), let page = h.page {
            return (frame, page.x)
        }
        if let m = editor.master { return (m.id, m.x) }
        return editor.page(at: p).map { ($0.id, $0.x) }
    }

    /// Makes the layer of a draw drag, inside an undo group that the drag ends.
    func makeDrawn(_ d: Drag) -> Drag {
        guard case .draw(let start, nil, _, let moved, let tool, let s) = d, let kind = tool.kind, let parent = parent(at: start) else { return d }
        editor.beginGroup()
        guard let id = editor.apply(.create(parent: parent.id, kind: kind, x: start.x - parent.dx, y: start.y, w: 0, h: 0)).first else {
            editor.endGroup()
            return d
        }
        if kind == .text { editor.apply(.set(id: id, Editor.insets)) }
        editor.select([id])
        return .draw(start: start, id: id, dx: parent.dx, moved: moved, tool: tool, snaps: s)
    }

    /// The in- and out-port of a single selected text frame that can thread, on the canvas.
    func ports() -> (node: Node, in: CGPoint?, out: CGPoint)? {
        guard editor.tool == .move, editor.selection.count == 1, editor.editing == nil, let n = editor.selected.first, n.kind == .text else { return nil }
        if n.sizing.horizontal == .hug && n.sizing.vertical == .hug && n.prev == nil && n.next == nil { return nil }
        let p = Handles.ports(view, editor.shown(n))
        return (n, n.prev != nil ? p.in : nil, p.out)
    }

    func port(at q: CGPoint) -> (side: Handles.Port, node: Node)? {
        guard let p = ports(), let side = Handles.port((p.in, p.out), at: q) else { return nil }
        return (side, p.node)
    }

    /// The text frame under `p`, innermost first.
    func textUnder(_ p: CGPoint) -> String? {
        hit(p).path.last { editor.nodes[$0]?.node.kind == .text }
    }

    /// Starts to drag a new guide out of a ruler.
    func beginGuide(axis: XY) {
        window?.makeFirstResponder(self)
        drag = .guide(axis: axis, page: editor.pageID ?? "", dx: 0, index: -1, grouped: false)
    }

    /// A double click edits the selected text at the click, enters a group, or picks.
    func doubleClick(_ p: CGPoint) {
        guard let id = pick(p, .double) else { return }
        if let n = editor.nodes[id]?.node, n.kind == .text, editor.selection.contains(id) {
            let i = textIndex(id, at: p)
            editor.edit(id, anchor: i, focus: i)
            wakeCaret()
            return
        }
        editor.select([id])
    }
}
