import Foundation

/// The units that lengths show in, as the settings choose; see `web/src/settings.ts`.
enum LengthUnit: String, CaseIterable, Identifiable {
    case mm, cm, `in`, pt

    var id: Self { self }

    /// Points per unit.
    var pt: Double {
        switch self {
        case .mm: Units.ptPerMM
        case .cm: 10 * Units.ptPerMM
        case .in: 72
        case .pt: 1
        }
    }

    var title: String {
        switch self {
        case .mm: String(localized: "Millimetres")
        case .cm: String(localized: "Centimetres")
        case .in: String(localized: "Inches")
        case .pt: String(localized: "length.points", defaultValue: "Points", comment: "The length unit pt")
        }
    }
}

/// Lengths: the engine counts in pt, people in the unit of the settings.
enum Units {
    static let ptPerMM = 72 / 25.4
    /// The settings key of the length unit.
    static let key = "unit"

    static func mm(_ v: Double) -> Double { v * ptPerMM }

    static let a4 = CGSize(width: mm(210), height: mm(297))

    /// The length unit of the settings.
    static var unit: LengthUnit {
        UserDefaults.standard.string(forKey: key).flatMap(LengthUnit.init) ?? .mm
    }
}

extension Units {
    /// A length in pt as people read it, in the unit of the settings with up to one decimal.
    static func format(_ pt: Double, unit: LengthUnit = Units.unit) -> String {
        (pt / unit.pt).formatted(.number.precision(.fractionLength(0...1))) + " " + unit.rawValue
    }
}
