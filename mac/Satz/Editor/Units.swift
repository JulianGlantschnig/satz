import Foundation

/// Lengths: the engine counts in pt, people in mm, cm, in or px.
enum Units {
    static let ptPerMM = 72 / 25.4

    static func mm(_ v: Double) -> Double { v * ptPerMM }

    static let a4 = CGSize(width: mm(210), height: mm(297))
}
