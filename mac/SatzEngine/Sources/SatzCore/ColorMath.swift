import Foundation
import SatzEngine

/// A palette seen from a layer with its modes, which swatches and variables resolve in.
public struct Scope: Sendable {
    public var swatches: [Swatch]
    public var collections: [Collection]
    public var variables: [Variable]
    public var modes: Modes

    public init(_ snapshot: Snapshot, modes: Modes = [:]) {
        swatches = snapshot.swatches
        collections = snapshot.collections
        variables = snapshot.variables
        self.modes = modes
    }

    public static let empty = Scope(swatches: [], collections: [], variables: [], modes: [:])

    init(swatches: [Swatch], collections: [Collection], variables: [Variable], modes: Modes) {
        (self.swatches, self.collections, self.variables, self.modes) = (swatches, collections, variables, modes)
    }

    var json: String {
        struct Out: Encodable {
            var swatches: [Swatch]
            var collections: [Collection]
            var variables: [Variable]
            var textStyles: [String] = []
            var modes: Modes
        }
        let data = (try? JSONEncoder().encode(Out(swatches: swatches, collections: collections, variables: variables, modes: modes))) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Hue in degrees, saturation and value in 0...1.
public struct HSV: Equatable, Sendable {
    public var h: Double
    public var s: Double
    public var v: Double
    public init(_ h: Double, _ s: Double, _ v: Double) { (self.h, self.s, self.v) = (h, s, v) }
}

/// Colours as the colour picker and the paint lists work with them; see `web/src/color.ts`.
public enum ColorMath {
    /// The process colour a swatch or variable stands for in `scope`.
    @MainActor
    public static func resolve(_ c: Color, _ scope: Scope) -> Color {
        switch c {
        case .rgb, .cmyk: return c
        default:
            guard let json = try? JSON(encoding: c).encodedString(),
                let out = try? SatzEngine.resolve(color: json, scope: scope.json),
                let color = try? JSONDecoder().decode(Color.self, from: Data(out.utf8))
            else { return c }
            return color
        }
    }

    /// The screen colour as 0xRRGGBB.
    @MainActor
    public static func rgb(_ c: Color, _ scope: Scope) -> UInt32 {
        switch resolve(c, scope) {
        case .rgb(let v): return v >> 8
        case .cmyk(let k, _) where k.count == 4: return previewCMYK(Float(k[0]), Float(k[1]), Float(k[2]), Float(k[3]))
        default: return 0
        }
    }

    /// The colour of `mode` closest to the screen colour `rgb`, with the alpha of `like`.
    @MainActor
    public static func fromRGB(_ rgb: UInt32, like: Color, mode: ColorMode) -> Color {
        if mode == .rgb { return Color.rgb(rgb << 8 | 0xff).with(alpha: like.alpha) }
        return .cmyk(separateRGB(rgb).map { (Double($0) * 100).rounded() / 100 }, alpha: like.alpha)
    }

    /// `"black"`, `"white"` or `"gray"` in `mode`.
    @MainActor
    public static func neutral(_ name: String, _ mode: ColorMode) -> Color {
        guard let out = try? SatzEngine.neutral(name: name, mode: "\"\(mode.rawValue)\""),
            let c = try? JSONDecoder().decode(Color.self, from: Data(out.utf8))
        else { return .black }
        return c
    }

    public static func hsv(_ rgb: UInt32) -> HSV {
        let (r, g, b) = (Double(rgb >> 16 & 0xff) / 255, Double(rgb >> 8 & 0xff) / 255, Double(rgb & 0xff) / 255)
        let v = max(r, g, b)
        let d = v - min(r, g, b)
        var h = 0.0
        if d != 0 {
            if v == r { h = ((g - b) / d + 6).truncatingRemainder(dividingBy: 6) } else if v == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        }
        return HSV(h * 60, v == 0 ? 0 : d / v, v)
    }

    public static func rgb(_ c: HSV) -> UInt32 {
        func f(_ n: Double) -> UInt32 {
            let k = (n + c.h / 60).truncatingRemainder(dividingBy: 6)
            return UInt32(((c.v - c.v * c.s * max(0, min(k, 4 - k, 1))) * 255).rounded())
        }
        return f(5) << 16 | f(3) << 8 | f(1)
    }

    public static func hex(_ rgb: UInt32) -> String { String(format: "%06X", rgb & 0xffffff) }

    /// The colour of a hex text such as `#FA0` or `ffaa00`.
    public static func parseHex(_ text: String) -> UInt32? {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return v
    }

    /// CMYK in % as "C:20 M:40 Y:0 K:10".
    public static func cmykText(_ cmyk: [Double]) -> String {
        zip("CMYK", cmyk).map { "\($0):\(($1 * 1000).rounded() / 10)".replacingOccurrences(of: ".0", with: "") }.joined(separator: " ")
    }

    /// CMYK 0...1 from four values in %, such as "20, 40, 0, 10", "C20 M40 Y0 K10" or
    /// "20% 40% 0% 10%"; nil for anything else.
    public static func parseCMYK(_ text: String) -> [Double]? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #":\s*"#, with: "", options: .regularExpression)
        let parts = cleaned.split(whereSeparator: { " ,/\t".contains($0) }).map(String.init)
        guard parts.count == 4 else { return nil }
        var out: [Double] = []
        for (i, p) in parts.enumerated() {
            var s = p
            if let f = s.first, f.isLetter {
                guard String(f).uppercased() == String(Array("CMYK")[i]) else { return nil }
                s.removeFirst()
            }
            if s.hasSuffix("%") { s.removeLast() }
            guard let v = Double(s), v >= 0, v <= 100 else { return nil }
            out.append(v / 100)
        }
        return out
    }

    /// A linear gradient across the unit box through its centre, 0° left to right, 90° top to bottom.
    public static func linear(_ degrees: Double) -> [Double] {
        let a = degrees * .pi / 180
        let (dx, dy) = (cos(a), sin(a))
        return [dx, dy, -dy, dx, 0.5 - dx / 2, 0.5 - dy / 2]
    }

    public static let radial: [Double] = [0.5, 0, 0, 0.5, 0.5, 0.5]

    /// The angle of a linear gradient's transform.
    public static func angle(_ t: [Double]) -> Double { t.count >= 2 ? atan2(t[1], t[0]) * 180 / .pi : 0 }

    /// `p` as a paint of `type`, its colour and stops kept as far as they fit.
    public static func retype(_ p: Fill, _ type: FillKind) -> Fill {
        guard type != p.type else { return p }
        var q = p
        q.type = type
        if type == .solid {
            q.color = p.stops.first?.color ?? p.color
            return q
        }
        q.stops = p.stops.count > 1 ? p.stops : [Fill.Stop(at: 0, color: p.color), Fill.Stop(at: 1, color: p.color.with(alpha: 0))]
        q.transform = type == .linear ? linear(90) : radial
        return q
    }

    /// `stops` with a new stop halfway along the widest gap, in the colour of the stop before it.
    public static func split(_ stops: [Fill.Stop]) -> [Fill.Stop] {
        let s = stops.sorted { $0.at < $1.at }
        guard s.count >= 2 else { return s }
        var k = 0
        for i in 1..<(s.count - 1) where s[i + 1].at - s[i].at > s[k + 1].at - s[k].at { k = i }
        var out = s
        out.insert(Fill.Stop(at: (s[k].at + s[k + 1].at) / 2, color: s[k].color), at: k + 1)
        return out
    }
}
