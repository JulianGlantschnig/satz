import Foundation

/// Rasters for print and drawing: lines, dots, squares, millimetre paper and more, with a
/// secondary raster, punch holes and a header, in millimetres; after the raster generator of
/// raster.brosemedien.de (`grid-types.js`, `export.js`).
public enum RasterGrid {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case lines, dots, squares, mm, iso, hex, polar, music, ruled, log
    }

    public enum Style: String, Codable, Sendable, CaseIterable { case solid, dashed, dotted }
    public enum Target: String, Codable, Sendable, CaseIterable { case all, horizontal, vertical }
    public enum Curve: String, Codable, Sendable, CaseIterable { case none, wave, arc }
    public enum Punch: String, Codable, Sendable, CaseIterable { case none, two, four, spiral }
    public enum Position: String, Codable, Sendable, CaseIterable {
        case topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight
    }

    /// The settings of a raster. Lengths are in mm, colours `#RRGGBB`.
    public struct Spec: Codable, Equatable, Sendable {
        /// The template it came from, or the user's name for it.
        public var name = ""
        public var kind = Kind.lines
        public var marginTop = 10.0, marginRight = 10.0, marginBottom = 10.0, marginLeft = 10.0
        // Lines and the type's own spacings.
        public var hSpacing = 10.0, vSpacing = 10.0
        public var dotSpacing = 5.0, dotSize = 0.6
        public var isoSpacing = 10.0
        public var hexSize = 8.0
        public var polarStep = 10.0, polarRays = 24
        public var musicLineGap = 2.5, musicSystemGap = 14.0
        /// Class 1 to 3 of school ruling, 4 for single lines.
        public var ruledClass = 2, ruledScale = 1.0
        public var logDecadesX = 3, logDecadesY = 3
        public var thickness = 0.25
        public var color = "#1A1A1A"
        public var axisColors = false
        public var colorH = "#CC3333", colorV = "#1A1A1A"
        public var style = Style.solid
        /// Every n-th line heavier, 0 for none.
        public var emphasize = 0
        // Secondary raster.
        public var secondary = false
        public var secondaryKind = Kind.dots
        public var secondarySpacing = 20.0, secondaryThickness = 0.4
        public var secondaryColor = "#CCCCCC"
        // Rotation and curvature.
        public var rotation = 0.0
        public var rotationTarget = Target.all
        public var curve = Curve.none
        public var curveAmplitude = 3.0, curveFrequency = 1.0
        public var punch = Punch.none
        // Header.
        public var header = false
        public var headerText = ""
        public var headerPosition = Position.topCenter
        public var headerSize = 11.0
        public var headerDate = false
        public var headerFont: Typeface?

        public init() {}

        public init(from decoder: Decoder) throws {
            // Settings missing from an older raster keep their defaults.
            let c = try decoder.container(keyedBy: CodingKeys.self)
            var s = Spec()
            func get<T: Decodable>(_ key: CodingKeys, _ path: WritableKeyPath<Spec, T>) {
                if let v = try? c.decodeIfPresent(T.self, forKey: key) { s[keyPath: path] = v }
            }
            get(.name, \.name)
            get(.kind, \.kind)
            get(.marginTop, \.marginTop); get(.marginRight, \.marginRight); get(.marginBottom, \.marginBottom); get(.marginLeft, \.marginLeft)
            get(.hSpacing, \.hSpacing); get(.vSpacing, \.vSpacing); get(.dotSpacing, \.dotSpacing); get(.dotSize, \.dotSize)
            get(.isoSpacing, \.isoSpacing); get(.hexSize, \.hexSize); get(.polarStep, \.polarStep); get(.polarRays, \.polarRays)
            get(.musicLineGap, \.musicLineGap); get(.musicSystemGap, \.musicSystemGap); get(.ruledClass, \.ruledClass); get(.ruledScale, \.ruledScale)
            get(.logDecadesX, \.logDecadesX); get(.logDecadesY, \.logDecadesY); get(.thickness, \.thickness); get(.color, \.color)
            get(.axisColors, \.axisColors); get(.colorH, \.colorH); get(.colorV, \.colorV); get(.style, \.style); get(.emphasize, \.emphasize)
            get(.secondary, \.secondary); get(.secondaryKind, \.secondaryKind); get(.secondarySpacing, \.secondarySpacing)
            get(.secondaryThickness, \.secondaryThickness); get(.secondaryColor, \.secondaryColor)
            get(.rotation, \.rotation); get(.rotationTarget, \.rotationTarget); get(.curve, \.curve)
            get(.curveAmplitude, \.curveAmplitude); get(.curveFrequency, \.curveFrequency); get(.punch, \.punch)
            get(.header, \.header); get(.headerText, \.headerText); get(.headerPosition, \.headerPosition); get(.headerSize, \.headerSize)
            get(.headerDate, \.headerDate); get(.headerFont, \.headerFont)
            self = s
        }

        public var json: String {
            (try? String(decoding: JSONEncoder().encode(self), as: UTF8.self)) ?? "{}"
        }

        public static func from(json: String) -> Spec? {
            try? JSONDecoder().decode(Spec.self, from: Data(json.utf8))
        }
    }

    /// Lines, circles and dots of one colour, weight and style, as a display-list path in mm.
    public struct Stroke: Equatable, Sendable {
        public var path: [Double]
        /// Stroke weight in mm, 0 for a filled path.
        public var weight: Double
        public var color: String
        public var style: Style
        /// Filled rather than stroked: the dots.
        public var filled: Bool
        /// Part of the raster, which the area of the raster clips; holes and the header are not.
        public var clipped: Bool
    }

    /// A line of the header with its baseline at `y`.
    public struct Label: Equatable, Sendable {
        public enum Anchor: Sendable { case start, middle, end }
        public var x, y: Double
        public var text: String
        /// In pt.
        public var size: Double
        public var anchor: Anchor
        public var color: String
    }

    public struct Drawing: Equatable, Sendable {
        public var strokes: [Stroke] = []
        public var labels: [Label] = []
    }

    // MARK: - Geometry

    private enum Axis { case h, v, other, deco }
    private enum Layer { case main, secondary, deco }

    private struct Op {
        enum Shape { case line(Double, Double, Double, Double), path([(Double, Double)]), circle(Double, Double, Double), dot(Double, Double, Double) }
        var shape: Shape
        var axis: Axis
        var weight: Double = 1
        var layer: Layer = .main
        var color: String?
        var absolute: Double?
    }

    private struct Area {
        var w, h: Double
        var x0, x1, y0, y1, d: Double
        init(_ w: Double, _ h: Double) {
            let d = hypot(w, h)
            (self.w, self.h, self.d) = (w, h, d)
            (x0, x1, y0, y1) = (w / 2 - d / 2, w / 2 + d / 2, h / 2 - d / 2, h / 2 + d / 2)
        }
    }

    /// From `start` on by `step` both ways as far as `lo` and `hi`.
    private static func steps(_ start: Double, _ step: Double, _ lo: Double, _ hi: Double) -> [Double] {
        guard step > 0 else { return [] }
        var out: [Double] = []
        var p = start
        while p <= hi + 1e-9 { out.append(p); p += step }
        p = start - step
        while p >= lo - 1e-9 { out.append(p); p -= step }
        return out
    }

    private static func emphasis(_ i: Int, _ every: Int) -> Double {
        every >= 2 && abs(i) % every == 0 ? 1.8 : 1
    }

    private static func curvedH(_ y: Double, _ b: Area, _ s: Spec, curve: Curve) -> Op.Shape {
        guard curve != .none, s.curveAmplitude > 0 else { return .line(b.x0, y, b.x1, y) }
        let w = b.x1 - b.x0, period = b.w / max(0.0001, s.curveFrequency)
        let n = max(40, Int((w / 2).rounded()))
        return .path((0...n).map { i in
            let x = b.x0 + Double(i) / Double(n) * w
            let dy = curve == .wave ? sin(x / period * 2 * .pi) : sin(min(1, max(0, x / b.w)) * .pi)
            return (x, y + dy * s.curveAmplitude)
        })
    }

    private static func curvedV(_ x: Double, _ b: Area, _ s: Spec, curve: Curve) -> Op.Shape {
        guard curve != .none, s.curveAmplitude > 0 else { return .line(x, b.y0, x, b.y1) }
        let h = b.y1 - b.y0, period = b.h / max(0.0001, s.curveFrequency)
        let n = max(40, Int((h / 2).rounded()))
        return .path((0...n).map { i in
            let y = b.y0 + Double(i) / Double(n) * h
            let dx = curve == .wave ? sin(y / period * 2 * .pi) : sin(min(1, max(0, y / b.h)) * .pi)
            return (x + dx * s.curveAmplitude, y)
        })
    }

    /// The ops of one raster of `kind`; `curve` bends lines, staves and ruling.
    private static func grid(_ kind: Kind, _ s: Spec, _ b: Area, curve: Curve) -> [Op] {
        var ops: [Op] = []
        func lineH(_ y: Double, _ weight: Double) {
            guard y >= b.y0 - 1e-9, y <= b.y1 + 1e-9 else { return }
            ops.append(Op(shape: curvedH(y, b, s, curve: curve), axis: .h, weight: weight))
        }
        switch kind {
        case .lines, .squares:
            let hs = max(0.1, s.hSpacing), vs = max(0.1, s.vSpacing)
            for y in steps(0, hs, b.y0, b.y1) {
                ops.append(Op(shape: curvedH(y, b, s, curve: curve), axis: .h, weight: emphasis(Int((y / hs).rounded()), s.emphasize)))
            }
            for x in steps(0, vs, b.x0, b.x1) {
                ops.append(Op(shape: curvedV(x, b, s, curve: curve), axis: .v, weight: emphasis(Int((x / vs).rounded()), s.emphasize)))
            }
        case .dots:
            let sp = max(0.5, s.dotSpacing), r = max(0.05, s.dotSize / 2)
            for y in steps(0, sp, b.y0, b.y1) {
                for x in steps(0, sp, b.x0, b.x1) { ops.append(Op(shape: .dot(x, y, r), axis: .other)) }
            }
        case .mm:
            for (step, weight) in [(1.0, 0.4), (5, 0.8), (10, 1.6)] {
                for y in steps(0, step, b.y0, b.y1) { ops.append(Op(shape: .line(b.x0, y, b.x1, y), axis: .h, weight: weight)) }
                for x in steps(0, step, b.x0, b.x1) { ops.append(Op(shape: .line(x, b.y0, x, b.y1), axis: .v, weight: weight)) }
            }
        case .iso:
            let sp = max(1, s.isoSpacing), t = tan(Double.pi / 6), dy = sp / cos(Double.pi / 6)
            for x in steps(0, sp, b.x0, b.x1) { ops.append(Op(shape: .line(x, b.y0, x, b.y1), axis: .v)) }
            var c = (floor((b.y0 - t * b.x1) / dy)) * dy
            while c <= b.y1 - t * b.x0 + 1e-9 {
                ops.append(Op(shape: .line(b.x0, t * b.x0 + c, b.x1, t * b.x1 + c), axis: .other))
                c += dy
            }
            c = floor((b.y0 + t * b.x0) / dy) * dy
            while c <= b.y1 + t * b.x1 + 1e-9 {
                ops.append(Op(shape: .line(b.x0, -t * b.x0 + c, b.x1, -t * b.x1 + c), axis: .other))
                c += dy
            }
        case .hex:
            let r = max(2, s.hexSize), w = r * 3.0.squareRoot(), row = 2 * r * 0.75
            var cy = floor(b.y0 / row) * row
            var i = Int((cy / row).rounded())
            while cy <= b.y1 + r {
                let offset = Double(((i % 2) + 2) % 2) * w / 2
                var cx = floor((b.x0 - offset) / w) * w + offset
                while cx <= b.x1 + w {
                    // Each hexagon as a closed path; neighbours share sides.
                    let corners = (0...6).map { k -> (Double, Double) in
                        let a = Double(60 * k - 90) * .pi / 180
                        return (cx + r * cos(a), cy + r * sin(a))
                    }
                    ops.append(Op(shape: .path(corners), axis: .other))
                    cx += w
                }
                cy += row
                i += 1
            }
        case .polar:
            let (cx, cy) = (b.w / 2, b.h / 2), most = b.d / 2, step = max(1, s.polarStep)
            var r = step
            while r <= most { ops.append(Op(shape: .circle(cx, cy, r), axis: .other)); r += step }
            let rays = max(0, s.polarRays)
            for i in 0..<rays {
                let a = Double(i) / Double(rays) * 2 * .pi
                ops.append(Op(shape: .line(cx, cy, cx + cos(a) * most, cy + sin(a) * most), axis: .other))
            }
        case .music:
            let gap = max(1, s.musicLineGap), cycle = gap * 4 + max(2, s.musicSystemGap)
            var y = floor(b.y0 / cycle) * cycle
            while y <= b.y1 + 1e-9 {
                for i in 0..<5 { lineH(y + Double(i) * gap, 1) }
                y += cycle
            }
        case .ruled:
            let scale = max(0.5, s.ruledScale)
            let (heights, gap): ([Double], Double) = switch s.ruledClass {
            case 1: ([4, 4, 4], 4)
            case 2: ([3, 3, 3], 3)
            case 3: ([2.5, 2.5, 2.5], 2.5)
            default: ([9], 0)
            }
            let hs = heights.map { $0 * scale }, cycle = hs.reduce(0, +) + gap * scale
            var y = floor(b.y0 / cycle) * cycle
            while y <= b.y1 + 1e-9 {
                var at = y
                lineH(at, 1.4)
                at += hs[0]
                if hs.count == 3 {
                    lineH(at, 0.9); at += hs[1]
                    lineH(at, 1.4); at += hs[2]
                    lineH(at, 1.0)
                }
                y += cycle
            }
        case .log:
            let dx = max(1, s.logDecadesX), dy = max(1, s.logDecadesY)
            let weight = { (n: Int) in n == 1 ? 1.6 : n == 5 ? 1.0 : 0.5 }
            for d in 0..<dx {
                for n in 1...9 {
                    let x = (Double(d) + log10(Double(n))) / Double(dx) * b.w
                    ops.append(Op(shape: .line(x, b.y0, x, b.y1), axis: .v, weight: weight(n)))
                }
            }
            ops.append(Op(shape: .line(b.w, b.y0, b.w, b.y1), axis: .v, weight: 1.6))
            for d in 0..<dy {
                for n in 1...9 {
                    let y = b.h - (Double(d) + log10(Double(n))) / Double(dy) * b.h
                    ops.append(Op(shape: .line(b.x0, y, b.x1, y), axis: .h, weight: weight(n)))
                }
            }
            ops.append(Op(shape: .line(b.x0, 0, b.x1, 0), axis: .h, weight: 1.6))
        }
        return ops
    }

    /// The holes along the spine: in the margin when it is at least 6 mm, else 8 mm into the raster.
    private static func holes(_ s: Spec, _ b: Area, spine margin: Double) -> [Op] {
        guard s.punch != .none else { return [] }
        let x = margin >= 6 ? -margin + min(margin / 2, 8) : 8
        let c = b.h / 2
        var ys: [Double] = switch s.punch {
        case .two: [c - 40, c + 40]
        case .four: [c - 120, c - 40, c + 40, c + 120]
        case .spiral: Array(stride(from: 6.0, through: b.h - 6, by: 6))
        case .none: []
        }
        ys = ys.filter { $0 >= 4 && $0 <= b.h - 4 }
        let r = s.punch == .spiral ? 1.2 : 3
        let grey = "#888888"
        return ys.flatMap { y in
            [
                Op(shape: .circle(x, y, r), axis: .deco, weight: 0.8, layer: .deco, color: grey),
                Op(shape: .line(x - 1.5, y, x + 1.5, y), axis: .deco, weight: 0.4, layer: .deco, color: grey),
                Op(shape: .line(x, y - 1.5, x, y + 1.5), axis: .deco, weight: 0.4, layer: .deco, color: grey),
            ]
        }
    }

    private static func header(_ s: Spec, _ b: Area, date: Date) -> [Label] {
        let text = s.headerText.trimmingCharacters(in: .whitespaces)
        guard s.header, !text.isEmpty || s.headerDate else { return [] }
        let size = max(6, s.headerSize), mm = size * 25.4 / 72, pad = 3.0
        let top = s.headerPosition.rawValue.hasPrefix("top")
        let y = top ? mm + 1 : b.h - 1
        let ink = "#1A1A1A"
        var out: [Label] = []
        if !text.isEmpty {
            let (x, anchor): (Double, Label.Anchor) = switch s.headerPosition {
            case .topLeft, .bottomLeft: (pad, .start)
            case .topRight, .bottomRight: (b.w - pad, .end)
            case .topCenter, .bottomCenter: (b.w / 2, .middle)
            }
            out.append(Label(x: x, y: y, text: text, size: size, anchor: anchor, color: ink))
        }
        if s.headerDate {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            out.append(Label(x: b.w - pad, y: y, text: f.string(from: date), size: size, anchor: .end, color: ink))
        }
        return out
    }

    /// The raster of `spec` in an area `width` × `height` mm, its origin at the area's top
    /// left. On a left page of a spread (`mirrored`) the holes and the header mirror to the
    /// spine on the right, and the margins of the spec swap sides.
    public static func build(_ spec: Spec, width: Double, height: Double, mirrored: Bool = false, date: Date = Date()) -> Drawing {
        let b = Area(width, height)
        var ops = grid(spec.kind, spec, b, curve: spec.curve)
        if spec.secondary {
            var t = spec
            t.hSpacing = spec.secondarySpacing
            t.vSpacing = spec.secondarySpacing
            t.dotSpacing = spec.secondarySpacing
            t.dotSize = max(0.3, spec.secondaryThickness * 1.5)
            t.emphasize = 0
            let second = grid(spec.secondaryKind, t, b, curve: .none).map { op in
                var op = op
                op.layer = .secondary
                op.color = spec.secondaryColor
                op.absolute = spec.secondaryThickness
                return op
            }
            ops = second + ops
        }
        // Rotation turns the raster, not the holes and the header.
        if spec.rotation != 0 {
            let a = spec.rotation * .pi / 180, (sn, cs) = (sin(a), cos(a)), (cx, cy) = (width / 2, height / 2)
            func turn(_ x: Double, _ y: Double) -> (Double, Double) {
                let (dx, dy) = (x - cx, y - cy)
                return (cx + dx * cs - dy * sn, cy + dx * sn + dy * cs)
            }
            ops = ops.map { op in
                let turns = switch spec.rotationTarget {
                case .all: true
                case .horizontal: op.axis == .h
                case .vertical: op.axis == .v
                }
                guard turns else { return op }
                var op = op
                switch op.shape {
                case .line(let x1, let y1, let x2, let y2):
                    let (a, b) = turn(x1, y1), (c, d) = turn(x2, y2)
                    op.shape = .line(a, b, c, d)
                case .path(let points): op.shape = .path(points.map { turn($0.0, $0.1) })
                case .circle(let x, let y, let r):
                    let (a, b) = turn(x, y)
                    op.shape = .circle(a, b, r)
                case .dot(let x, let y, let r):
                    let (a, b) = turn(x, y)
                    op.shape = .dot(a, b, r)
                }
                return op
            }
        }
        let spine = mirrored ? spec.marginRight : spec.marginLeft
        var deco = holes(spec, b, spine: spine)
        var labels = header(spec, b, date: date)
        if mirrored {
            deco = deco.map { op in
                var op = op
                switch op.shape {
                case .line(let x1, let y1, let x2, let y2): op.shape = .line(width - x1, y1, width - x2, y2)
                case .circle(let x, let y, let r): op.shape = .circle(width - x, y, r)
                default: break
                }
                return op
            }
            labels = labels.map { l in
                var l = l
                l.x = width - l.x
                l.anchor = l.anchor == .start ? .end : l.anchor == .end ? .start : .middle
                return l
            }
        }
        return Drawing(strokes: strokes(ops + deco, spec), labels: labels)
    }

    /// The ops gathered into one path per colour, weight and style, in their order.
    private static func strokes(_ ops: [Op], _ s: Spec) -> [Stroke] {
        var out: [Stroke] = []
        var index: [String: Int] = [:]
        for op in ops {
            let filled: Bool
            if case .dot = op.shape { filled = true } else { filled = false }
            let color = op.color ?? (s.axisColors && op.axis == .h ? s.colorH : s.axisColors && op.axis == .v ? s.colorV : s.color)
            let weight = filled ? 0 : op.absolute ?? max(0.05, s.thickness * op.weight)
            let style = op.layer == .deco ? Style.solid : s.style
            let key = "\(op.layer)|\(color)|\(weight)|\(style)|\(filled)"
            let i = index[key] ?? {
                out.append(Stroke(path: [], weight: weight, color: color, style: style, filled: filled, clipped: op.layer != .deco))
                index[key] = out.count - 1
                return out.count - 1
            }()
            out[i].path += path(op.shape)
        }
        return out
    }

    private static let move = 0.0, line = 1.0, cubic = 4.0, close = 5.0

    /// Where layers snap to the main raster in its area `width` × `height` mm: its upright
    /// lines and its dots, in mm from the area's top left.
    public static func snapLines(_ spec: Spec, width: Double, height: Double, mirrored: Bool = false) -> (x: [Double], y: [Double]) {
        var s = spec
        s.secondary = false
        s.punch = .none
        s.header = false
        var xs = Set<Double>(), ys = Set<Double>()
        let inside = { (v: Double, most: Double) in v >= -1e-6 && v <= most + 1e-6 }
        for stroke in build(s, width: width, height: height, mirrored: mirrored).strokes where stroke.clipped {
            let p = stroke.path
            var i = 0
            var at: (Double, Double)?
            var points = 0
            while i < p.count {
                switch p[i] {
                case move:
                    at = (p[i + 1], p[i + 2])
                    points = 1
                    i += 3
                case line:
                    // Only the two points of a straight line; a curve has many.
                    if let a = at, points == 1, i + 3 >= p.count || p[i + 3] == move {
                        let b = (p[i + 1], p[i + 2])
                        if abs(a.0 - b.0) < 1e-9, inside(a.0, width) { xs.insert((a.0 * 1000).rounded() / 1000) }
                        if abs(a.1 - b.1) < 1e-9, inside(a.1, height) { ys.insert((a.1 * 1000).rounded() / 1000) }
                    }
                    points += 1
                    i += 3
                case cubic:
                    if stroke.filled, let a = at, points == 1 {
                        // A dot: its centre, r left of its first point.
                        let r = abs(p[i + 5] - a.0) + abs(p[i + 6] - a.1) > 0 ? abs(a.0 - p[i + 5]) : 0
                        let c = (a.0 - r, a.1)
                        if inside(c.0, width) { xs.insert((c.0 * 1000).rounded() / 1000) }
                        if inside(c.1, height) { ys.insert((c.1 * 1000).rounded() / 1000) }
                    }
                    points += 1
                    i += 7
                default: i += 1
                }
            }
        }
        return (xs.sorted(), ys.sorted())
    }

    private static func path(_ shape: Op.Shape) -> [Double] {
        switch shape {
        case .line(let x1, let y1, let x2, let y2): return [move, x1, y1, line, x2, y2]
        case .path(let p):
            guard let f = p.first else { return [] }
            return [move, f.0, f.1] + p.dropFirst().flatMap { [line, $0.0, $0.1] }
        case .circle(let x, let y, let r), .dot(let x, let y, let r):
            // Four quarters of cubic Béziers.
            let k = 0.5522847498 * r
            return [
                move, x + r, y,
                cubic, x + r, y + k, x + k, y + r, x, y + r,
                cubic, x - k, y + r, x - r, y + k, x - r, y,
                cubic, x - r, y - k, x - k, y - r, x, y - r,
                cubic, x + k, y - r, x + r, y - k, x + r, y,
                close,
            ]
        }
    }
}
