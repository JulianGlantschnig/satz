import Foundation

public enum ColorMode: String, Codable, Sendable, CaseIterable {
    case rgb, cmyk
}

/// RGB is 0xRRGGBBAA; CMYK components, tint and alpha are 0...1. A swatch's tint only
/// applies to spot colours; alpha multiplies what a swatch or variable holds.
public enum Color: Hashable, Sendable {
    case rgb(UInt32)
    case cmyk([Double], alpha: Double)
    case swatch(String, tint: Double, alpha: Double)
    case variable(String, alpha: Double)

    public static let black = Color.rgb(0x0000_00ff)
    public static let white = Color.rgb(0xffff_ffff)

    /// Alpha in 0...1.
    public var alpha: Double {
        switch self {
        case .rgb(let v): Double(v & 0xff) / 255
        case .cmyk(_, let a), .swatch(_, _, let a), .variable(_, let a): a
        }
    }

    public func with(alpha a: Double) -> Color {
        let a = min(1, max(0, a))
        switch self {
        case .rgb(let v): return .rgb(v & ~0xff | UInt32((a * 255).rounded()))
        case .cmyk(let c, _): return .cmyk(c, alpha: a)
        case .swatch(let s, let t, _): return .swatch(s, tint: t, alpha: a)
        case .variable(let v, _): return .variable(v, alpha: a)
        }
    }
}

extension Color: Codable {
    private enum Keys: String, CodingKey {
        case cmyk, alpha, swatch, tint, variable
    }

    public init(from decoder: Decoder) throws {
        if let v = try? decoder.singleValueContainer().decode(UInt32.self) {
            self = .rgb(v)
            return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        let alpha = try c.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
        if let cmyk = try c.decodeIfPresent([Double].self, forKey: .cmyk) {
            self = .cmyk(cmyk, alpha: alpha)
        } else if let s = try c.decodeIfPresent(String.self, forKey: .swatch) {
            self = .swatch(s, tint: try c.decodeIfPresent(Double.self, forKey: .tint) ?? 1, alpha: alpha)
        } else {
            self = .variable(try c.decode(String.self, forKey: .variable), alpha: alpha)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .rgb(let v):
            var c = encoder.singleValueContainer()
            try c.encode(v)
        case .cmyk(let cmyk, let alpha):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(cmyk, forKey: .cmyk)
            try c.encode(alpha, forKey: .alpha)
        case .swatch(let s, let tint, let alpha):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(s, forKey: .swatch)
            try c.encode(tint, forKey: .tint)
            try c.encode(alpha, forKey: .alpha)
        case .variable(let v, let alpha):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(v, forKey: .variable)
            try c.encode(alpha, forKey: .alpha)
        }
    }
}
