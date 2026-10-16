import AppKit
import SatzCore

/// The selection, hover, marquee, snap guides and distances over the pages, in canvas points.
extension CanvasView {
    var accent: CGColor { NSColor.controlAccentColor.cgColor }

    func drawOverlay(_ ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineWidth(1)
        ctx.setStrokeColor(accent)

        // The picked guide.
        if let g = editor.guide, let s = editor.sheets.first(where: { $0.id == g.page }) {
            let list = g.axis == .x ? s.guides.x : s.guides.y
            if g.index < list.count {
                ctx.setLineWidth(2)
                if g.axis == .x {
                    let x = view.toCanvas(CGPoint(x: s.x + list[g.index], y: 0)).x
                    ctx.strokeLineSegments(between: [CGPoint(x: x, y: -1e5), CGPoint(x: x, y: 1e5)])
                } else {
                    let y = view.toCanvas(CGPoint(x: 0, y: list[g.index])).y
                    ctx.strokeLineSegments(between: [CGPoint(x: -1e5, y: y), CGPoint(x: 1e5, y: y)])
                }
                ctx.setLineWidth(1)
            }
        }

        let selected = editor.selected
        for n in selected where !n.hidden {
            if let (a, b) = Editor.ends(n) {
                let dx = editor.dx(n.id)
                line(ctx, CGPoint(x: a.x + dx, y: a.y), CGPoint(x: b.x + dx, y: b.y))
            } else {
                outline(ctx, editor.shown(n))
            }
        }
        if let id = overlay.hover ?? editor.hover, !editor.selection.contains(id), let n = editor.nodes[id]?.node, drag == nil {
            ctx.setLineWidth(2)
            if let (a, b) = Editor.ends(n) {
                let dx = editor.dx(n.id)
                line(ctx, CGPoint(x: a.x + dx, y: a.y), CGPoint(x: b.x + dx, y: b.y))
            } else {
                outline(ctx, editor.shown(n))
            }
            ctx.setLineWidth(1)
        }

        if case .marquee(let start, let end, _) = drag {
            let r = Handles.rect(view.toCanvas(start), view.toCanvas(end)).rect
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor)
            ctx.fill(r)
            ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5))
        }

        let handles = selectionHandles()
        if let (a, b) = handles.line, !isMoving {
            line(ctx, a, b)
            square(ctx, view.toCanvas(a), Handles.size)
            square(ctx, view.toCanvas(b), Handles.size)
        } else if let box = handles.box, !isMoving {
            turned(ctx, box) {
                let r = self.screen(box)
                ctx.stroke(r)
                for x in [r.minX, r.maxX] { for y in [r.minY, r.maxY] { self.square(ctx, CGPoint(x: x, y: y), Handles.size) } }
                if r.height > 4 * Handles.size { for x in [r.minX, r.maxX] { self.square(ctx, CGPoint(x: x, y: r.midY), Handles.size) } }
                if r.width > 4 * Handles.size { for y in [r.minY, r.maxY] { self.square(ctx, CGPoint(x: r.midX, y: y), Handles.size) } }
                for p in handles.radii { self.dot(ctx, p) }
            }
        }

        // The ports of a selected text frame and the lines of its thread.
        if let ports = ports() {
            let n = ports.node
            let frames = editor.nodes.values.map(\.node).filter { $0.kind == .text && $0.story == n.story }
            ctx.setStrokeColor(accent)
            for f in frames {
                guard let next = f.next, let g = frames.first(where: { $0.id == next }) else { continue }
                ctx.strokeLineSegments(between: [Handles.ports(view, editor.shown(f)).out, Handles.ports(view, editor.shown(g)).in])
            }
            if let p = ports.in { port(ctx, p, state: .threaded) }
            port(ctx, ports.out, state: n.overset == true ? .overset : n.next != nil ? .threaded : .open)
        }
        // Labels under the selection: overset words and master overrides.
        for n in selected where !n.hidden && editor.editing == nil {
            let b = editor.covered(n)
            let bottom = view.toCanvas(CGPoint(x: b.x, y: b.maxY))
            let right = view.toCanvas(CGPoint(x: b.maxX, y: b.maxY))
            if n.overrideOf != nil {
                _ = drawLabel(ctx, String(localized: "Override"), at: CGPoint(x: bottom.x + 36, y: bottom.y + 17), fill: CGColor(srgbRed: 0.55, green: 0.35, blue: 0.95, alpha: 1))
            }
            let words = n.kind == .text ? editor.oversetWords(n) : 0
            if words > 0 {
                let text = String(localized: "+\(words) words")
                let w = label(text).size().width + 10
                _ = drawLabel(ctx, text, at: CGPoint(x: right.x - w / 2, y: right.y + 17), fill: Self.overset)
            }
        }

        // Snap guides and distances.
        let magenta = CGColor(srgbRed: 1, green: 0.2, blue: 0.55, alpha: 1)
        ctx.setStrokeColor(magenta)
        for g in overlay.snapped {
            if g.axis == .x {
                line(ctx, CGPoint(x: g.at, y: g.from), CGPoint(x: g.at, y: g.to))
            } else {
                line(ctx, CGPoint(x: g.from, y: g.at), CGPoint(x: g.to, y: g.at))
            }
        }
        var labels: [CGRect] = []
        for m in overlay.measures {
            if m.dashed { ctx.setLineDash(phase: 0, lengths: [3, 3]) }
            line(ctx, CGPoint(x: m.x1, y: m.y1), CGPoint(x: m.x2, y: m.y2))
            ctx.setLineDash(phase: 0, lengths: [])
            guard !m.dashed else { continue }
            let horizontal = m.y1 == m.y2
            var c = view.toCanvas(CGPoint(x: horizontal ? (m.x1 + m.x2) / 2 : m.x1, y: horizontal ? m.y1 : (m.y1 + m.y2) / 2))
            let text = Units.format(m.length)
            let size = label(text).size()
            while labels.contains(where: { abs($0.midX - c.x) < ($0.width + size.width + 10) / 2 && abs($0.midY - c.y) < 20 }) { c.y += 20 }
            labels.append(drawLabel(ctx, text, at: c, fill: magenta))
        }
        if let size = overlay.size {
            let c = view.toCanvas(CGPoint(x: size.x + size.w / 2, y: size.y + size.h))
            _ = drawLabel(ctx, "\(Units.format(size.w)) × \(Units.format(size.h))", at: CGPoint(x: c.x, y: c.y + 18), fill: accent)
        }
        if let turn = overlay.turn, let p = overlay.pointer {
            let degrees = Int(((turn.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360).rounded())
            _ = drawLabel(ctx, "\(degrees)°", at: CGPoint(x: p.x + 28, y: p.y + 20), fill: accent)
        }
    }

    static let overset = CGColor(srgbRed: 1, green: 0.42, blue: 0.37, alpha: 1)

    enum PortState { case threaded, overset, open }

    /// A text frame's port: threaded shows an arrow, overset a red plus, open a plus.
    private func port(_ ctx: CGContext, _ c: CGPoint, state: PortState) {
        square(ctx, c, Handles.port)
        let (x, y) = (c.x.rounded(.down) + 0.5, c.y.rounded(.down) + 0.5)
        ctx.saveGState()
        switch state {
        case .overset, .open:
            ctx.setStrokeColor(state == .overset ? Self.overset : accent)
            ctx.setLineWidth(state == .overset ? 2 : 1.5)
            ctx.strokeLineSegments(between: [CGPoint(x: x - 3, y: y), CGPoint(x: x + 3, y: y), CGPoint(x: x, y: y - 3), CGPoint(x: x, y: y + 3)])
        case .threaded:
            ctx.setFillColor(accent)
            ctx.move(to: CGPoint(x: x - 2, y: y - 3))
            ctx.addLine(to: CGPoint(x: x + 3, y: y))
            ctx.addLine(to: CGPoint(x: x - 2, y: y + 3))
            ctx.closePath()
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    private var isMoving: Bool {
        if case .move(_, _, true, _, _) = drag { return true }
        return false
    }

    /// `b` in canvas points, on whole points plus a half so that 1 pt lines are sharp.
    func screen(_ b: Box) -> CGRect {
        let tl = view.toCanvas(CGPoint(x: b.x, y: b.y))
        return CGRect(x: tl.x.rounded() + 0.5, y: tl.y.rounded() + 0.5, width: (b.w * view.zoom).rounded(), height: (b.h * view.zoom).rounded())
    }

    /// Draws `body` turned as `b` is, around its centre on the canvas.
    func turned(_ ctx: CGContext, _ b: Box, _ body: () -> Void) {
        ctx.saveGState()
        if b.rotation != 0 {
            let c = view.toCanvas(b.center)
            ctx.translateBy(x: c.x, y: c.y)
            ctx.rotate(by: -b.rotation * .pi / 180)
            ctx.translateBy(x: -c.x, y: -c.y)
        }
        body()
        ctx.restoreGState()
    }

    private func outline(_ ctx: CGContext, _ b: Box) {
        turned(ctx, b) { ctx.stroke(screen(b)) }
    }

    /// A line between two points of the spread.
    private func line(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint) {
        ctx.strokeLineSegments(between: [view.toCanvas(a), view.toCanvas(b)])
    }

    private func square(_ ctx: CGContext, _ c: CGPoint, _ size: Double) {
        let r = CGRect(x: (c.x - size / 2).rounded(.down) + 0.5, y: (c.y - size / 2).rounded(.down) + 0.5, width: size, height: size)
        ctx.setFillColor(.white)
        ctx.fill(r)
        ctx.setStrokeColor(accent)
        ctx.stroke(r)
    }

    private func dot(_ ctx: CGContext, _ c: CGPoint) {
        let r = CGRect(x: c.x - Handles.size / 2, y: c.y - Handles.size / 2, width: Handles.size, height: Handles.size)
        ctx.setFillColor(.white)
        ctx.fillEllipse(in: r)
        ctx.setStrokeColor(accent)
        ctx.strokeEllipse(in: r)
    }

    func label(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
    }

    /// A pill with `text` centred at `c`; returns where it went.
    func drawLabel(_ ctx: CGContext, _ text: String, at c: CGPoint, fill: CGColor) -> CGRect {
        let s = label(text)
        let size = s.size()
        let r = CGRect(x: c.x - size.width / 2 - 5, y: c.y - 9, width: size.width + 10, height: 18)
        ctx.setFillColor(fill)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.fillPath()
        NSGraphicsContext.saveGraphicsState()
        s.draw(at: CGPoint(x: r.minX + 5, y: r.midY - size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
        return r
    }
}
