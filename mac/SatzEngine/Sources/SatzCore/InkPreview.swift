import CoreGraphics
import Foundation
import SatzEngine

/// What the preflight shows of the inks: of the pages on screen their plates and marks,
/// of the whole document the highest coverage of each plate; see `exportWorker.ts`.
public struct InkPreview: Sendable {
    /// Which plates show and what is marked over them.
    public struct Options: Hashable, Sendable {
        /// Bit 0 for C … bit 3 for K, then the document's spot colours in `spots` order.
        public var on: UInt32 = UInt32(Int32.max)
        /// Marks in magenta where the coverage is above the ink limit.
        public var over = true
        /// Hatches the colours outside the gamut.
        public var gamut = true

        public init() {}

        public func shows(_ plate: Int) -> Bool { on & (1 << UInt32(plate)) != 0 }
    }

    /// A page as it prints at `ppi`, over its bleed.
    public struct Sheet: @unchecked Sendable {
        public var page: String
        public var width: Int
        public var height: Int
        public var image: CGImage
        /// The total coverage of each pixel in percent, row by row.
        public var coverage: [Float]

        /// The coverage in percent at `p` in pt from the top left of the bleed.
        public func coverage(at p: CGPoint, ppi: Double) -> Int? {
            let x = Int((p.x * ppi / 72).rounded(.down))
            let y = Int((p.y * ppi / 72).rounded(.down))
            guard x >= 0, y >= 0, x < width, y < height else { return nil }
            return Int(coverage[y * width + x].rounded())
        }
    }

    public var ppi: Double
    public var sheets: [Sheet]
    /// The names of the spot colours of all pages, in the order of their bits after K.
    public var spots: [String]
    /// The highest coverage of C, M, Y, K and each spot colour in percent.
    public var max: [Float]
    /// The highest total coverage of any page in percent.
    public var highest: Float
}

/// Makes `InkPreview`s on a queue of its own and keeps the inks of each page there
/// until the page prints differently.
public final class InkPreviewer: @unchecked Sendable {
    public static let ppi: Double = 48

    private struct Page {
        var key: UInt64
        var inks: Inks?
        var names: [String]
        var max: [Float]
        var ink: Float
    }

    private let queue = DispatchQueue(label: "satz.inks", qos: .userInitiated)
    /// Only used on `queue`.
    private var pages: [String: Page] = [:]
    /// The print hash of each page as the queue will have it, only used on the main actor.
    @MainActor private var keys: [String: UInt64] = [:]
    /// The pages whose inks the queue keeps, only used on the main actor.
    @MainActor private var held: Set<String> = []

    public init() {}

    /// Calls `done` with the preview of `shown` among the pages `printed` (page id and
    /// `Engine.printed` hash, in order). `copy` runs only when a page prints differently
    /// than the last time.
    @MainActor
    public func preview(
        _ copy: () -> DocumentCopy, printed: [(String, UInt64)], shown: [String],
        options: InkPreview.Options, limit: Double,
        done: @escaping @MainActor @Sendable (Result<InkPreview, Error>) -> Void
    ) {
        let printed = printed.map { Pair(id: $0.0, key: $0.1) }
        let stale = printed.contains { keys[$0.id] != $0.key } || shown.contains { !held.contains($0) }
        let doc = stale ? copy() : nil
        keys = Dictionary(printed.map { ($0.id, $0.key) }, uniquingKeysWith: { a, _ in a })
        held = Set(shown)
        queue.async { [self] in
            let result = Result { try make(doc, printed: printed, shown: shown, options: options, limit: Float(limit)) }
            Task { @MainActor in
                if case .failure = result {
                    self.keys = [:]
                    self.held = []
                }
                done(result)
            }
        }
    }

    private struct Pair: Sendable {
        var id: String
        var key: UInt64
    }

    private func make(_ doc: DocumentCopy?, printed: [Pair], shown: [String], options: InkPreview.Options, limit: Float) throws -> InkPreview {
        let ppi = Float(Self.ppi)
        var core: Core?
        func inks(_ id: String) throws -> Inks {
            if core == nil {
                guard let doc else { throw EngineError.Failed(message: "The document changed while its inks were read") }
                core = try doc.core()
            }
            guard let i = core!.inks(page: id, ppi: ppi) else { throw EngineError.Failed(message: "The page \(id) has no inks") }
            return i
        }
        var max: [String: Float] = [:]
        var names: [String] = []
        var highest: Float = 0
        for p in printed {
            if pages[p.id]?.key != p.key {
                let i = try inks(p.id)
                let ink = i.coverage().max() ?? 0
                pages[p.id] = Page(key: p.key, inks: i, names: ["C", "M", "Y", "K"] + i.spots(), max: i.max(), ink: ink)
            }
            let page = pages[p.id]!
            for (k, name) in page.names.enumerated() {
                if max[name] == nil { names.append(name) }
                max[name] = Swift.max(max[name] ?? 0, page.max[k])
            }
            highest = Swift.max(highest, page.ink)
        }
        let live = Set(printed.map(\.id))
        for (id, var page) in pages {
            if !live.contains(id) {
                pages[id] = nil
            } else if !shown.contains(id), page.inks != nil {
                page.inks = nil
                pages[id] = page
            }
        }
        let spots = Array(names.dropFirst(4))
        let sheets: [InkPreview.Sheet] = try shown.compactMap { id in
            guard var page = pages[id] else { return nil }
            let i = try page.inks ?? inks(id)
            page.inks = i
            pages[id] = page
            // The page's own plates, from the document's bits.
            var mask: UInt32 = 0
            for (k, name) in page.names.enumerated() {
                let bit = k < 4 ? k : 4 + (spots.firstIndex(of: name) ?? 0)
                if options.shows(bit) { mask |= 1 << UInt32(k) }
            }
            let (w, h) = (Int(i.width()), Int(i.height()))
            guard let image = Self.image(i.image(on: mask, limit: limit, over: options.over, gamut: options.gamut), width: w, height: h)
            else { return nil }
            return InkPreview.Sheet(page: id, width: w, height: h, image: image, coverage: i.coverage())
        }
        return InkPreview(ppi: Self.ppi, sheets: sheets, spots: spots, max: names.map { max[$0]! }, highest: highest)
    }

    /// Straight RGBA pixels as an image.
    static func image(_ rgba: Data, width: Int, height: Int) -> CGImage? {
        guard rgba.count == width * height * 4, let provider = CGDataProvider(data: rgba as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: Painter.srgb, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
