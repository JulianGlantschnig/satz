import Foundation

/// Lengths: the engine counts in pt, people in mm, cm, in or px.
enum Units {
    static let ptPerMM = 72 / 25.4

    static func mm(_ v: Double) -> Double { v * ptPerMM }

    static let a4 = CGSize(width: mm(210), height: mm(297))
}

extension Units {
    /// A length in pt as people read it, in mm with up to one decimal.
    static func format(_ pt: Double) -> String {
        let mm = pt / ptPerMM
        return mm.formatted(.number.precision(.fractionLength(0...1))) + " mm"
    }
}
