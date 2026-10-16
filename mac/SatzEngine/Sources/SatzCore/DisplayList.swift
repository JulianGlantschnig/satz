import Foundation

/// What the engine draws, decoded from the words of its display list; see
/// `engine/src/display_list.rs`, whose `encode` this reads.
public enum DisplayList {
    /// Path verbs: move and line take a point, cubic three, close none.
    public static let move: Float = 0
    public static let line: Float = 1
    public static let cubic: Float = 4
    public static let close: Float = 5

    /// Marks the font of a glyph run whose own font is missing, drawn in the bundled one.
    public static let missingFont: UInt32 = 1 << 31

    public struct Stop: Equatable, Sendable {
        public var at: Float
        /// The screen colour as straight sRGB and alpha in 0...1, [r, g, b, a].
        public var color: [Float]
    }

    public enum Paint: Equatable, Sendable {
        case solid([Float])
        /// Unit space maps into page space with `transform` [a b c d e f]: linear runs
        /// from (0, 0) to (1, 0), radial is the unit circle around (0, 0).
        case linear(transform: [Float], stops: [Stop])
        case radial(transform: [Float], stops: [Stop])
    }

    public struct Shadow: Equatable, Sendable {
        public var offset: [Float]
        /// Gaussian sigma in pt.
        public var blur: Float
        public var color: [Float]
    }

    public enum Op: Equatable, Sendable {
        case page(width: Float, height: Float, bleed: Float)
        /// `hash` changes whenever what the item draws does.
        case beginItem(item: UInt32, hash: UInt32)
        case endItem
        case fillPath(paint: Paint, path: [Float])
        case glyphRun(font: UInt32, size: Float, paint: Paint, glyphs: [UInt16], positions: [Float])
        /// The image `image` of `imageBytes`, whose unit square `transform` maps into page space.
        case image(image: UInt32, transform: [Float])
        case pushClip(path: [Float], invert: Bool)
        case popClip
        /// `cap` and `join` index [butt, round, square] and [miter, round, bevel].
        case strokePath(paint: Paint, width: Float, cap: UInt32, join: UInt32, path: [Float])
        /// Blur and shadow blurs are Gaussian sigmas in pt; `blend` indexes `Blend.allCases`.
        case pushLayer(hash: UInt32, opacity: Float, blend: UInt32, blur: Float, shadows: [Shadow])
        case popLayer
        /// The ops up to `endMask` are an alpha mask for the ops from there up to `popMask`.
        case beginMask
        case endMask
        case popMask
        case pushTransform([Float])
        case popTransform
    }

    public struct DecodeError: Error, CustomStringConvertible {
        public var description: String
    }

    public static func decode(_ data: Data) throws -> [Op] {
        try data.withUnsafeBytes { raw in
            var r = Reader(bytes: raw)
            return try r.ops()
        }
    }

    /// Index of the op that closes the one opened at `at`; `endMask` closes
    /// `beginMask` and opens up to `popMask`.
    public static func closing(_ ops: [Op], _ at: Int) -> Int {
        var depth = 1
        var i = at + 1
        while i < ops.count {
            switch ops[i] {
            case .popClip, .popLayer, .popMask, .popTransform, .endItem, .endMask:
                depth -= 1
                if depth == 0 { return i }
                if case .endMask = ops[i] { depth += 1 }
            case .pushClip, .pushLayer, .pushTransform, .beginMask, .beginItem:
                depth += 1
            default:
                break
            }
            i += 1
        }
        return ops.count
    }

    private struct Reader {
        let bytes: UnsafeRawBufferPointer
        var i = 0

        var count: Int { bytes.count / 4 }

        /// The engine writes little-endian words; `Data` need not align them.
        func at(_ k: Int) -> UInt32 {
            UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 4 * k, as: UInt32.self))
        }

        mutating func word() throws -> UInt32 {
            guard i < count else { throw DecodeError(description: "display list ends inside an op") }
            defer { i += 1 }
            return at(i)
        }

        mutating func float() throws -> Float { Float(bitPattern: try word()) }

        mutating func floats(_ n: Int) throws -> [Float] {
            guard n >= 0, i + n <= count else { throw DecodeError(description: "display list ends inside an op") }
            let out = (i..<i + n).map { Float(bitPattern: at($0)) }
            i += n
            return out
        }

        mutating func paint() throws -> Paint {
            let type = try word()
            if type == 0 { return .solid(try floats(4)) }
            let transform = try floats(6)
            let n = Int(try word())
            var stops: [Stop] = []
            stops.reserveCapacity(n)
            for _ in 0..<n {
                stops.append(Stop(at: try float(), color: try floats(4)))
            }
            return type == 1 ? .linear(transform: transform, stops: stops) : .radial(transform: transform, stops: stops)
        }

        mutating func path() throws -> [Float] { try floats(Int(try word())) }

        mutating func ops() throws -> [Op] {
            var ops: [Op] = []
            while i < count {
                let start = i
                switch try word() {
                case 0:
                    let f = try floats(3)
                    ops.append(.page(width: f[0], height: f[1], bleed: f[2]))
                case 1:
                    ops.append(.beginItem(item: try word(), hash: try word()))
                case 2: ops.append(.endItem)
                case 3:
                    let p = try paint()
                    ops.append(.fillPath(paint: p, path: try path()))
                case 4:
                    let font = try word()
                    let size = try float()
                    let p = try paint()
                    let n = Int(try word())
                    var glyphs: [UInt16] = []
                    glyphs.reserveCapacity(n)
                    for k in 0..<(n + 1) / 2 {
                        let w = try word()
                        glyphs.append(UInt16(w & 0xffff))
                        if 2 * k + 1 < n { glyphs.append(UInt16(w >> 16)) }
                    }
                    ops.append(.glyphRun(font: font, size: size, paint: p, glyphs: glyphs, positions: try floats(2 * n)))
                case 5:
                    ops.append(.image(image: try word(), transform: try floats(6)))
                case 6:
                    let invert = try word() == 1
                    ops.append(.pushClip(path: try path(), invert: invert))
                case 7: ops.append(.popClip)
                case 8:
                    let p = try paint()
                    let width = try float()
                    let cap = try word()
                    let join = try word()
                    ops.append(.strokePath(paint: p, width: width, cap: cap, join: join, path: try path()))
                case 9:
                    let hash = try word()
                    let opacity = try float()
                    let blend = try word()
                    let blur = try float()
                    let n = Int(try word())
                    var shadows: [Shadow] = []
                    for _ in 0..<n {
                        shadows.append(Shadow(offset: try floats(2), blur: try float(), color: try floats(4)))
                    }
                    ops.append(.pushLayer(hash: hash, opacity: opacity, blend: blend, blur: blur, shadows: shadows))
                case 10: ops.append(.popLayer)
                case 11: ops.append(.beginMask)
                case 12: ops.append(.endMask)
                case 13: ops.append(.popMask)
                case 14: ops.append(.pushTransform(try floats(6)))
                case 15: ops.append(.popTransform)
                case let code:
                    throw DecodeError(description: "display list: bad op \(code) at word \(start)")
                }
            }
            return ops
        }
    }
}
