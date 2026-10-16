import AppKit
import SatzCore

/// A ruler along the top or left of the canvas in mm, with the selection's extent
/// shaded and the guides marked; a drag out of it makes a guide.
final class RulerView: NSView {
    static let thickness: CGFloat = 20

    let horizontal: Bool
    weak var canvas: CanvasView?

    init(horizontal: Bool) {
        self.horizontal = horizontal
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let canvas else { return }
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let view = canvas.view
        // The ruler's 0 sits at the left edge of the spread's first page and its top.
        let left = canvas.editor.sheets.map(\.x).min() ?? 0
        let offset = horizontal ? canvas.frame.minX - frame.minX : canvas.frame.minY - frame.minY
        let origin = (horizontal ? view.x + left * view.zoom : view.y) + offset
        let scale = view.zoom * Units.ptPerMM
        let length = horizontal ? bounds.width : bounds.height
        let t = Self.thickness

        if let sel = selectionExtent() {
            ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.14).cgColor)
            let (a, b) = (sel.0 + offset, sel.1 + offset)
            ctx.fill(horizontal ? CGRect(x: a, y: 0, width: b - a, height: t) : CGRect(x: 0, y: a, width: t, height: b - a))
        }

        let steps: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200]
        let step = steps.first { $0 * scale >= 7 } ?? 500
        let major = [0.1, 1, 10, 100].contains(step) ? 10 : 5
        let first = Int((-origin / scale / step).rounded(.down))
        let end = Int(((length - origin) / scale / step).rounded(.up))
        guard end > first, end - first < 5000 else { return }
        ctx.setFillColor(NSColor.secondaryLabelColor.cgColor)
        for n in first..<end {
            let tick: CGFloat = n % major == 0 ? 9 : n % 5 == 0 ? 5 : 3
            let p = (Double(n) * step * scale + origin).rounded()
            ctx.fill(horizontal ? CGRect(x: p, y: t - tick, width: 1, height: tick) : CGRect(x: t - tick, y: p, width: tick, height: 1))
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        var n = Int((Double(first) / Double(major)).rounded(.up)) * major
        while n < end {
            let v = (Double(n) * step * 10).rounded() / 10
            let label = NSAttributedString(string: v.formatted(.number.grouping(.never)), attributes: attrs)
            let p = (Double(n) * step * scale + origin).rounded()
            if horizontal {
                label.draw(at: CGPoint(x: p + 3, y: 0))
            } else {
                NSGraphicsContext.saveGraphicsState()
                ctx.translateBy(x: 0, y: p - 3)
                ctx.rotate(by: -.pi / 2)
                label.draw(at: CGPoint(x: 0, y: 0))
                NSGraphicsContext.restoreGraphicsState()
            }
            n += major
        }

        // The guides of the pages.
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.2, blue: 0.55, alpha: 1))
        for s in canvas.editor.sheets {
            for g in horizontal ? s.guides.x.map({ $0 + s.x }) : s.guides.y {
                let p = ((horizontal ? view.x : view.y) + g * view.zoom + offset).rounded()
                ctx.fill(horizontal ? CGRect(x: p - 0.5, y: 0, width: 1, height: t) : CGRect(x: 0, y: p - 0.5, width: t, height: 1))
            }
        }
        ctx.setFillColor(NSColor.separatorColor.cgColor)
        ctx.fill(horizontal ? CGRect(x: 0, y: t - 1, width: bounds.width, height: 1) : CGRect(x: t - 1, y: 0, width: 1, height: bounds.height))
    }

    /// The selection's extent along the ruler in the canvas's points.
    private func selectionExtent() -> (CGFloat, CGFloat)? {
        guard let canvas else { return nil }
        let nodes = canvas.editor.selected
        guard !nodes.isEmpty else { return nil }
        let b = Box.around(nodes.map { Handles.upright(canvas.editor.shown($0)) })
        let v = canvas.view
        return horizontal ? (v.x + b.x * v.zoom, v.x + b.maxX * v.zoom) : (v.y + b.y * v.zoom, v.y + b.maxY * v.zoom)
    }

    // A drag out of the ruler makes a guide across it.

    override func mouseDown(with event: NSEvent) {
        guard let canvas else { return }
        canvas.editor.showsGrids = true
        canvas.beginGuide(axis: horizontal ? .y : .x)
    }

    override func mouseDragged(with event: NSEvent) { canvas?.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { canvas?.mouseUp(with: event) }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: horizontal ? .resizeUpDown : .resizeLeftRight)
    }
}

/// The canvas with its rulers, which show or hide.
final class CanvasContainer: NSView {
    let canvas: CanvasView
    let top = RulerView(horizontal: true)
    let left = RulerView(horizontal: false)
    private let corner = NSView()

    var showsRulers = true {
        didSet {
            guard showsRulers != oldValue else { return }
            top.isHidden = !showsRulers
            left.isHidden = !showsRulers
            corner.isHidden = !showsRulers
            needsLayout = true
        }
    }

    init(canvas: CanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        top.canvas = canvas
        left.canvas = canvas
        corner.wantsLayer = true
        corner.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        for v in [canvas, top, left, corner] { addSubview(v) }
        canvas.viewChanged = { [weak self] in
            self?.top.needsDisplay = true
            self?.left.needsDisplay = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let t = showsRulers ? RulerView.thickness : 0
        top.frame = CGRect(x: t, y: 0, width: bounds.width - t, height: t)
        left.frame = CGRect(x: 0, y: t, width: t, height: bounds.height - t)
        corner.frame = CGRect(x: 0, y: 0, width: t, height: t)
        canvas.frame = CGRect(x: t, y: t, width: bounds.width - t, height: bounds.height - t)
    }
}
