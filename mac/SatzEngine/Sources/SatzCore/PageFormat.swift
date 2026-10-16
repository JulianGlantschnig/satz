import Foundation

/// Paper formats in mm, portrait; see `web/src/Start.tsx`.
public enum PageFormat {
    public static let all: [(name: String, width: Double, height: Double)] = [
        ("A2", 420, 594), ("A3", 297, 420), ("A4", 210, 297), ("A5", 148, 210), ("A6", 105, 148), ("DL", 99, 210), ("Letter", 215.9, 279.4),
    ]

    static let ptPerMM = 72 / 25.4

    /// The name of the format of a `w` by `h` pt page in either orientation, or nil.
    public static func name(width w: Double, height h: Double) -> String? {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.5 }
        return all.first { near(min(w, h), $0.width * ptPerMM) && near(max(w, h), $0.height * ptPerMM) }?.name
    }

    /// The size in pt of the format `name`, landscape when asked.
    public static func size(_ name: String, landscape: Bool) -> (width: Double, height: Double)? {
        guard let f = all.first(where: { $0.name == name }) else { return nil }
        let (a, b) = (f.width * ptPerMM, f.height * ptPerMM)
        return landscape ? (b, a) : (a, b)
    }
}
