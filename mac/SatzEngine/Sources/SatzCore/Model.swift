import Foundation

// The document as the engine's snapshot shows it; see `engine/src/doc/draw.rs` and
// `web/src/model.ts`, which this mirrors.

public enum FillKind: String, Codable, Sendable {
    case solid, linear, radial, image
}

/// Gradients map their unit space, and images the unit square they fill, into the
/// layer's unit box with `transform`; `image` is the hash of an image fill's file,
/// and `adjust` its brightness, contrast and saturation in -1...1.
public struct Fill: Codable, Hashable, Sendable {
    public struct Stop: Codable, Hashable, Sendable {
        public var at: Double
        public var color: Color
        public init(at: Double, color: Color) {
            self.at = at
            self.color = color
        }
    }

    public var type: FillKind
    public var color: Color
    public var stops: [Stop]
    public var transform: [Double]
    public var visible: Bool
    public var image: String?
    public var adjust: [Double]?

    public init(
        type: FillKind = .solid, color: Color, stops: [Stop] = [], transform: [Double] = [1, 0, 0, 1, 0, 0],
        visible: Bool = true, image: String? = nil, adjust: [Double]? = nil
    ) {
        self.type = type
        self.color = color
        self.stops = stops
        self.transform = transform
        self.visible = visible
        self.image = image
        self.adjust = adjust
    }

    public static func solid(_ color: Color) -> Fill { Fill(color: color) }
}

public struct Effect: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case dropShadow, blur }
    public var type: Kind
    public var x: Double
    public var y: Double
    public var radius: Double
    public var color: Color
    public var visible: Bool

    public init(type: Kind, x: Double, y: Double, radius: Double, color: Color, visible: Bool = true) {
        (self.type, self.x, self.y, self.radius, self.color, self.visible) = (type, x, y, radius, color, visible)
    }
}

public enum Blend: String, Codable, Sendable, CaseIterable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn
    case hardLight, softLight, difference, exclusion, hue, saturation, color, luminosity
}

public enum LineStyle: String, Codable, Sendable, CaseIterable {
    case solid, dashed, dotted, wavy, zigzag
}

public enum StrokeAlign: String, Codable, Sendable, CaseIterable { case inside, center, outside }
public enum Join: String, Codable, Sendable, CaseIterable { case miter, round, bevel }
public enum Cap: String, Codable, Sendable, CaseIterable { case none, round, square }

/// How a frame's child follows the frame on resize.
public enum Constraint: String, Codable, Sendable, CaseIterable {
    case min, max, stretch, center, scale
}

public struct Constraints: Codable, Hashable, Sendable {
    public var horizontal: Constraint
    public var vertical: Constraint
}

public enum Direction: String, Codable, Sendable, CaseIterable { case none, horizontal, vertical }

/// Hug only applies to auto layout frames and text, fill only inside auto layout frames.
public enum Size: String, Codable, Sendable, CaseIterable { case fixed, hug, fill }

/// On text, hugging both sides is auto width and hugging the height auto height.
public struct Sizing: Codable, Hashable, Sendable {
    public var horizontal: Size
    public var vertical: Size
    public init(horizontal: Size, vertical: Size) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

public enum AlignMain: String, Codable, Sendable, CaseIterable { case start, center, end, spaceBetween }
public enum AlignCross: String, Codable, Sendable, CaseIterable { case start, center, end }
public enum Wrap: String, Codable, Sendable, CaseIterable { case none, around, jump }
public enum VerticalAlign: String, Codable, Sendable, CaseIterable { case top, center, bottom }

public enum NodeKind: String, Codable, Sendable { case shape, text, group, frame }
public enum ShapeKind: String, Codable, Sendable { case rect, ellipse, polygon, star, path }

/// Chosen mode per collection; collections not listed use their first mode.
public typealias Modes = [String: String]

public struct ColumnRule: Codable, Hashable, Sendable {
    public var weight: Double
    public var color: Color
}

/// A layer. The fields of other kinds are nil.
public struct Node: Decodable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public var modes: Modes
    public var activeModes: Modes
    public var bindings: [String: String]
    /// The master layer this page layer overrides.
    public var overrideOf: String?
    /// Effective pixels per inch of the coarsest visible image fill.
    public var ppi: Double?
    public var hidden: Bool
    public var locked: Bool
    /// Drawn on the canvas but not exported or preflighted, with the children.
    public var nonprinting: Bool
    /// The settings of the raster this group was made from, as JSON.
    public var raster: String?
    public var keepRatio: Bool
    /// Degrees counterclockwise around the centre, with the children.
    public var rotation: Double
    public var wrap: Wrap
    public var wrapOffsetX: Double
    public var wrapOffsetY: Double
    /// The upright box [x, y, w, h] on the page that the layer covers.
    public var bounds: [Double]

    // Style
    public var fills: [Fill]
    public var strokes: [Fill]
    public var strokeWeight: Double
    public var strokeAlign: StrokeAlign
    /// The weights of the top, right, bottom and left side, or nil for `strokeWeight` all round.
    public var strokeSides: [Double]?
    public var join: Join
    public var cap: Cap
    public var lineStyle: LineStyle
    public var arrowStart: Bool
    public var arrowEnd: Bool
    public var opacity: Double
    public var blend: Blend
    public var effects: [Effect]
    public var mask: Bool
    public var overprintFill: Bool
    public var overprintStroke: Bool
    public var constraints: Constraints

    // Layout
    public var direction: Direction
    public var gap: Double
    public var paddingTop: Double
    public var paddingRight: Double
    public var paddingBottom: Double
    public var paddingLeft: Double
    public var alignMain: AlignMain
    public var alignCross: AlignCross
    public var sizing: Sizing
    /// Left out of its parent's auto layout.
    public var absolute: Bool

    public var kind: NodeKind

    // Shape
    public var shape: ShapeKind?
    public var radius: Double?
    public var corners: [Double]?
    public var start: Double?
    public var sweep: Double?
    public var inner: Double?
    public var count: Int?
    public var ratio: Double?
    public var path: [Double]?

    // Frame
    public var clip: Bool?
    public var children: [Node]?

    // Text
    public var story: String?
    public var textStart: Int?
    public var textEnd: Int?
    public var prev: String?
    public var next: String?
    public var overset: Bool?
    public var insetTop: Double?
    public var insetRight: Double?
    public var insetBottom: Double?
    public var insetLeft: Double?
    public var columns: Int?
    public var gutter: Double?
    public var verticalAlign: VerticalAlign?
    public var baselineGrid: Double?
    public var baselineStart: Double?
    public var maxLines: Int?
    public var trim: Bool?
    public var columnRule: ColumnRule?
    public var minHeight: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, x, y, w, h, modes, activeModes, bindings, overrideOf, ppi, hidden, locked, nonprinting, raster
        case keepRatio, rotation, wrap, wrapOffsetX, wrapOffsetY, bounds
        case fills, strokes, strokeWeight, strokeAlign, strokeSides, join, cap, lineStyle
        case arrowStart, arrowEnd, opacity, blend, effects, mask, overprintFill, overprintStroke
        case constraints, direction, gap, paddingTop, paddingRight, paddingBottom, paddingLeft
        case alignMain, alignCross, sizing, absolute, kind
        case shape, radius, corners, start, sweep, inner, count, ratio, path, clip, children
        // A shape's arc `start` and a text frame's `start` share the key; see `init`.
        case story, end, prev, next, overset, insetTop, insetRight, insetBottom, insetLeft
        case columns, gutter, verticalAlign, baselineGrid, baselineStart, maxLines, trim
        case columnRule, minHeight
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys) throws -> T { try c.decode(T.self, forKey: k) }
        func o<T: Decodable>(_ k: CodingKeys) throws -> T? { try c.decodeIfPresent(T.self, forKey: k) }
        id = try d(.id)
        name = try d(.name)
        x = try d(.x)
        y = try d(.y)
        w = try d(.w)
        h = try d(.h)
        modes = try o(.modes) ?? [:]
        activeModes = try o(.activeModes) ?? [:]
        bindings = try o(.bindings) ?? [:]
        overrideOf = try o(.overrideOf)
        ppi = try o(.ppi)
        hidden = try o(.hidden) ?? false
        locked = try o(.locked) ?? false
        nonprinting = try o(.nonprinting) ?? false
        raster = try o(.raster)
        keepRatio = try o(.keepRatio) ?? false
        rotation = try o(.rotation) ?? 0
        wrap = try o(.wrap) ?? .none
        wrapOffsetX = try o(.wrapOffsetX) ?? 0
        wrapOffsetY = try o(.wrapOffsetY) ?? 0
        bounds = try o(.bounds) ?? [x, y, w, h]
        fills = try d(.fills)
        strokes = try d(.strokes)
        strokeWeight = try d(.strokeWeight)
        strokeAlign = try d(.strokeAlign)
        strokeSides = try o(.strokeSides)
        join = try d(.join)
        cap = try d(.cap)
        lineStyle = try d(.lineStyle)
        arrowStart = try d(.arrowStart)
        arrowEnd = try d(.arrowEnd)
        opacity = try d(.opacity)
        blend = try d(.blend)
        effects = try d(.effects)
        mask = try d(.mask)
        overprintFill = try d(.overprintFill)
        overprintStroke = try d(.overprintStroke)
        constraints = try d(.constraints)
        direction = try d(.direction)
        gap = try d(.gap)
        paddingTop = try d(.paddingTop)
        paddingRight = try d(.paddingRight)
        paddingBottom = try d(.paddingBottom)
        paddingLeft = try d(.paddingLeft)
        alignMain = try d(.alignMain)
        alignCross = try d(.alignCross)
        sizing = try d(.sizing)
        absolute = try d(.absolute)
        kind = try d(.kind)
        shape = try o(.shape)
        radius = try o(.radius)
        corners = try o(.corners)
        sweep = try o(.sweep)
        inner = try o(.inner)
        count = try o(.count)
        ratio = try o(.ratio)
        path = try o(.path)
        clip = try o(.clip)
        children = try o(.children)
        if kind == .text {
            textStart = try o(.start)
        } else {
            start = try o(.start)
        }
        story = try o(.story)
        textEnd = try o(.end)
        prev = try o(.prev)
        next = try o(.next)
        overset = try o(.overset)
        insetTop = try o(.insetTop)
        insetRight = try o(.insetRight)
        insetBottom = try o(.insetBottom)
        insetLeft = try o(.insetLeft)
        columns = try o(.columns)
        gutter = try o(.gutter)
        verticalAlign = try o(.verticalAlign)
        baselineGrid = try o(.baselineGrid)
        baselineStart = try o(.baselineStart)
        maxLines = try o(.maxLines)
        trim = try o(.trim)
        columnRule = try o(.columnRule)
        minHeight = try o(.minHeight)
    }

    public var isContainer: Bool { kind == .group || kind == .frame }

    /// Whether this is a path that does not close.
    public var isOpen: Bool { kind == .shape && shape == .path && !(path ?? []).contains(5) }

    /// Whether it has corners to round: a frame or a rectangle.
    public var isRounded: Bool { kind == .frame || (kind == .shape && shape == .rect) }

    /// The radii of the top left, top right, bottom right and bottom left corner.
    public var radii: [Double] {
        if let corners, !corners.isEmpty { return corners }
        let r = radius ?? 0
        return [r, r, r, r]
    }
}

public enum Side: String, Codable, Sendable { case left, right }

/// Ruler guides of a page: vertical ones at `x` from its left edge, horizontal ones at `y` from its top.
public struct Guides: Codable, Hashable, Sendable {
    public var x: [Double]
    public var y: [Double]
    public init(x: [Double] = [], y: [Double] = []) {
        self.x = x
        self.y = y
    }
}

/// Page numbers from a page on: `start` on it, counted in `style` after `prefix`.
public struct Section: Codable, Hashable, Sendable {
    public enum Style: String, Codable, Sendable, CaseIterable { case arabic, upperRoman, lowerRoman }
    public var start: Int
    public var style: Style
    public var prefix: String
    public init(start: Int, style: Style, prefix: String) {
        self.start = start
        self.style = style
        self.prefix = prefix
    }
}

/// `count` columns or rows between margins and gutters, or square cells of `size`, in pt.
public struct Grid: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable { case columns, rows, grid }
    public var kind: Kind
    public var count: Int
    public var gutter: Double
    public var margin: Double
    public var size: Double
    public init(kind: Kind, count: Int, gutter: Double, margin: Double, size: Double) {
        self.kind = kind
        self.count = count
        self.gutter = gutter
        self.margin = margin
        self.size = size
    }
}

/// A page or a master: `name` is a master's, `master` the one a page draws under its
/// layers and `detached` the master layers it overrides; `side` is the side of its
/// spread a page is on with facing pages, `x` where its left edge sits on the spread.
public struct Page: Decodable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var width: Double
    public var height: Double
    public var bleed: Double
    public var side: Side?
    public var x: Double
    public var master: String?
    public var detached: [String]
    public var grids: [Grid]
    public var guides: Guides
    public var section: Section?
    public var modes: Modes
    public var children: [Node]
}

public struct Swatch: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// A spot colour's `color` is its CMYK alternate.
    public var color: Color
    public var spot: Bool
}

public struct Collection: Codable, Hashable, Sendable, Identifiable {
    public struct Mode: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
    }
    public var id: String
    public var name: String
    public var modes: [Mode]
}

/// A font by its full name, family and style, and a hash of its bytes.
public struct Typeface: Codable, Hashable, Sendable {
    public var name: String
    public var family: String
    public var style: String
    public var hash: String
    public init(name: String, family: String, style: String, hash: String) {
        self.name = name
        self.family = family
        self.style = style
        self.hash = hash
    }
}

/// A variable's value: a colour, a number or a font (nil is the bundled one).
public enum Value: Hashable, Sendable {
    case color(Color)
    case number(Double)
    case font(Typeface?)
}

extension Value: Codable {
    private enum Keys: String, CodingKey { case color, number, font }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let v = try c.decodeIfPresent(Color.self, forKey: .color) {
            self = .color(v)
        } else if let v = try c.decodeIfPresent(Double.self, forKey: .number) {
            self = .number(v)
        } else {
            self = .font(try c.decodeIfPresent(Typeface.self, forKey: .font))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .color(let v): try c.encode(v, forKey: .color)
        case .number(let v): try c.encode(v, forKey: .number)
        case .font(let v): try c.encode(v, forKey: .font)
        }
    }
}

/// One value per mode of its collection, all of one kind.
public struct Variable: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var collection: String
    public var name: String
    public var values: [String: Value]
}

/// A tab stop `at` pt from the column's left edge, with a leader repeated over the gap.
public struct Tab: Codable, Hashable, Sendable {
    public enum Align: String, Codable, Sendable, CaseIterable { case left, center, right, decimal }
    public var at: Double
    public var align: Align
    public var leader: String
}

/// What a character looks like. Sizes and spacing in pt, letter spacing in % of the
/// size; line height 0 is auto. `fill` replaces the layer's fills; `textStyle` ""
/// means none. Paragraph attributes come from each paragraph's first character.
public struct Attrs: Codable, Hashable, Sendable {
    public enum TextAlign: String, Codable, Sendable, CaseIterable { case left, center, right, justify }
    public enum Lang: String, Codable, Sendable, CaseIterable { case en, de, fr, it, es, nl }
    public enum TextCase: String, Codable, Sendable, CaseIterable { case original, upper, lower, title }
    public enum Decoration: String, Codable, Sendable, CaseIterable { case none, underline, strikethrough }
    public enum Position: String, Codable, Sendable, CaseIterable { case normal, superscript, `subscript` }
    public enum ListKind: String, Codable, Sendable, CaseIterable { case none, bullet, number }

    public var size: Double
    public var lineHeight: Double
    public var letterSpacing: Double
    public var paragraphSpacing: Double
    public var fill: Color?
    public var textStyle: String
    public var textAlign: TextAlign
    public var hyphenate: Bool
    public var lang: Lang
    public var font: Typeface?
    public var paragraphIndent: Double
    public var indentLeft: Double
    public var indentRight: Double
    public var spaceBefore: Double
    public var textCase: TextCase
    public var textDecoration: Decoration
    public var features: [String]
    public var position: Position
    public var baselineShift: Double
    public var dropLines: Int
    public var dropChars: Int
    public var keepLines: Int
    public var keepTogether: Bool
    public var keepNext: Bool
    public var tabs: [Tab]
    public var list: ListKind
    public var shading: Color?
}

/// `len` characters in UTF-16 code units that share their attributes.
public struct Span: Codable, Hashable, Sendable {
    public var len: Int
    public var attrs: Attrs

    private enum Keys: String, CodingKey { case len }

    public init(from decoder: Decoder) throws {
        len = try decoder.container(keyedBy: Keys.self).decode(Int.self, forKey: .len)
        attrs = try Attrs(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try attrs.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(len, forKey: .len)
    }
}

/// The text of a thread and its runs of equal attributes.
public struct Story: Codable, Hashable, Sendable {
    public var text: String
    public var spans: [Span]
}

public struct TextStyle: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var bindings: [String: String]
    public var attrs: Attrs

    private enum Keys: String, CodingKey { case id, name, bindings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        bindings = try c.decodeIfPresent([String: String].self, forKey: .bindings) ?? [:]
        attrs = try Attrs(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try attrs.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(bindings, forKey: .bindings)
    }
}

/// Something about the layer `layer` on the page or master `page` that may print wrong.
public struct Issue: Codable, Hashable, Sendable {
    public enum Problem: String, Codable, Sendable {
        case overset, shortOfBleed, rgb, gamut, missingFont, lowPpi, ink, nearTrim
    }
    public var page: String
    public var layer: String
    public var name: String
    public var problem: Problem
    public var font: String?
    public var ppi: Double?
    public var ink: Double?
    public var distance: Double?
}

public enum Preset: String, Codable, Sendable, CaseIterable { case screen, x4, x1a }

public struct MissingFont: Codable, Hashable, Sendable {
    public var font: Typeface
    public var stories: [String]
}

public struct Snapshot: Decodable, Sendable {
    public var pages: [Page]
    public var masters: [Page]
    public var facingPages: Bool
    /// The ids of the pages of each spread from left to right.
    public var spreads: [[String]]
    /// The story of each thread by its first frame.
    public var stories: [String: Story]
    public var rasterPpi: Double
    public var colorMode: ColorMode
    /// The name of the uploaded CMYK profile, nil for FOGRA51.
    public var profile: String?
    public var inkLimit: Double
    public var preset: Preset
    public var cropMarks: Bool
    public var includeBleed: Bool
    public var imagePpi: Double
    public var jpegQuality: Int
    public var swatches: [Swatch]
    public var collections: [Collection]
    public var variables: [Variable]
    public var textStyles: [TextStyle]
    /// The fonts text can be set in, the bundled one first.
    public var fonts: [Typeface]
    public var missingFonts: [MissingFont]
    /// The colours of each image by its hash: "Gray", "RGB" or "CMYK".
    public var images: [String: String]
    public var preflight: [Issue]
    public var canUndo: Bool
    public var canRedo: Bool

    public static func decode(_ json: String) throws -> Snapshot {
        try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
    }

    /// The page or master `id`.
    public func page(_ id: String) -> Page? {
        pages.first { $0.id == id } ?? masters.first { $0.id == id }
    }
}
