import Foundation
import SatzEngine

public typealias EngineError = SatzEngine.EngineError

/// A Satz document in the Rust engine. The engine keeps fonts, images and the colour
/// profile per thread, so a document lives on the main actor; exports make their own
/// on a thread of their own.
@MainActor
public final class Engine {
    let core: Core
    private var cached: (version: String, snapshot: Snapshot)?

    /// The document Satz shows on its first start.
    public static func sample() -> Engine { Engine(core: Core.sample()) }

    /// An empty CMYK document of `pages` pages `width` × `height` pt.
    public static func blank(width: Double, height: Double, pages: Int, facing: Bool) -> Engine {
        Engine(core: Core.blank(w: width, h: height, pages: UInt32(pages), facing: facing))
    }

    /// The document saved as `data`.
    public static func load(_ data: Data) throws -> Engine {
        Engine(core: try Core.load(bytes: data))
    }

    init(core: Core) {
        self.core = core
    }

    /// Applies `command` and returns the ids it made.
    @discardableResult
    public func apply(_ command: Command) throws -> [String] {
        try core.apply(command: command.json)
    }

    /// What the last command changed beyond what it was asked to.
    public var notes: [String] { core.notes() }

    /// Changes whenever the document does.
    public var version: String { core.version() }

    public var snapshot: Snapshot {
        get throws {
            let v = core.version()
            if let cached, cached.version == v { return cached.snapshot }
            let s = try Snapshot.decode(core.snapshot())
            cached = (v, s)
            return s
        }
    }

    public func save() -> Data { core.save() }

    /// Path from the topmost page child down to the deepest layer at `point` in pt;
    /// `tolerance` in pt widens the hit area of outlines.
    public func hit(page: String, at point: CGPoint, tolerance: Double) -> [String] {
        core.hit(page: page, x: point.x, y: point.y, tolerance: tolerance)
    }

    /// The layer of the page's master at `point` in pt that the page shows.
    public func masterHit(page: String, at point: CGPoint, tolerance: Double) -> String? {
        core.masterHit(page: page, x: point.x, y: point.y, tolerance: tolerance)
    }

    /// The display list of the page or master `page`, as words.
    public func displayList(page: String) -> Data { core.displayList(page: page) }

    /// The version of the display list of `page`, which changes only with it.
    public func listVersion(page: String) -> UInt32 { core.listVersion(page: page) }

    /// The display list of the page as its inverted C, M and Y plate, or its K plate.
    public func plate(page: String, k: Bool) -> Data { core.plate(page: page, k: k) }

    /// Shows or hides the nonprinting layers in the display lists of the canvas.
    public func showNonprinting(shown: Bool) { core.showNonprinting(shown: shown) }

    /// [x, top, bottom] in pt of a caret before the UTF-16 `index` of the text `id`.
    public func caret(_ id: String, index: Int) throws -> [Double] {
        try core.caret(id: id, index: UInt32(index))
    }

    /// The transform [a b c d e f] that turns the layer `id` on its page.
    public func turn(_ id: String) throws -> [Float] { try core.turn(id: id) }

    /// Whether the text frame `to` can join the thread after `from`.
    public func canThread(from: String, to: String) -> Bool { core.canThread(from: from, to: to) }

    /// The frame of the thread of the text `id` that holds the UTF-16 `index`.
    public func textFrame(_ id: String, index: Int) throws -> String {
        try core.textFrame(id: id, index: UInt32(index))
    }

    /// The UTF-16 index of the character boundary of the text `id` nearest `point` in pt.
    public func textIndex(_ id: String, at point: CGPoint) throws -> Int {
        Int(try core.textIndex(id: id, x: point.x, y: point.y))
    }

    /// UTF-16 start and end of the line of the text `id` that holds `index`.
    public func textLine(_ id: String, index: Int) throws -> Range<Int> {
        let l = try core.textLine(id: id, index: UInt32(index))
        return Int(l[0])..<Int(l[1])
    }

    /// Display list of the selection from `anchor` to `focus` in the text `id` on
    /// `page`, or of a caret `caretWidth` pt wide when they are equal.
    public func textOverlay(_ id: String, anchor: Int, focus: Int, caretWidth: Float, page: String) throws -> Data {
        try core.textOverlay(id: id, anchor: UInt32(anchor), focus: UInt32(focus), caretWidth: caretWidth, page: page)
    }

    /// The inks of the page `page` as it prints at `ppi`.
    public func inks(page: String, ppi: Float) -> Inks? { core.inks(page: page, ppi: ppi) }

    /// A hash of the page as it prints; its inks change only with it.
    public func printed(page: String) -> UInt64? { core.printed(page: page) }

    /// The page as a PNG at `ppi`.
    public func png(page: String, ppi: Float) -> Data? { core.png(page: page, ppi: ppi) }

    /// The pages at `indices` as a PDF titled `title`, made at `date`.
    public func pdf(title: String, date: Date = Date(), indices: [Int]) -> Data {
        core.pdf(title: title, date: Self.iso(date), indices: indices.map { UInt32($0) })
    }

    /// A ZIP for the printer: the document, the PDF of the pages, its fonts and images.
    public func package(title: String, date: Date = Date(), indices: [Int]) -> Data {
        core.package(title: title, date: Self.iso(date), indices: indices.map { UInt32($0) })
    }

    /// Screen colours of CMYK in the document's print condition, for `InkTable`.
    public func lut() -> Data { core.lut() }

    /// Makes `icc` the CMYK profile of the document, or FOGRA51 for nil.
    public func setProfile(_ icc: Data?) throws { try core.setProfile(icc: icc) }

    /// Adds a TrueType, OpenType, WOFF or WOFF2 font and returns its typeface.
    public func addFont(_ data: Data) throws -> Typeface {
        try JSONDecoder().decode(Typeface.self, from: Data(core.addFont(bytes: data).utf8))
    }

    public func removeFont(hash: String) throws { try core.removeFont(hash: hash) }

    public struct ImageInfo: Decodable, Sendable {
        public var hash: String
        public var width: Int
        public var height: Int
        /// "Gray", "RGB" or "CMYK".
        public var space: String
    }

    /// Adds a PNG or JPEG file to the document's images, for `Command.placeImage`.
    public func addImage(_ data: Data) throws -> ImageInfo {
        try JSONDecoder().decode(ImageInfo.self, from: Data(core.addImage(bytes: data).utf8))
    }

    static func iso(_ date: Date) -> String {
        date.ISO8601Format(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon))
    }
}

/// The file of the image `id` of display lists.
public func imageBytes(_ id: UInt32) -> Data { SatzEngine.imageBytes(id: id) }

/// The file of the font `id` of display lists.
public func fontBytes(_ id: UInt32) -> Data { SatzEngine.fontBytes(id: id) }

/// The number of font ids, removed ones included.
public func fontsAdded() -> Int { Int(SatzEngine.fontsAdded()) }

/// The letters that the page numbers of the master `name` show.
public func masterPrefix(_ name: String) -> String { SatzEngine.prefix(name: name) }

/// Screen preview of a CMYK colour as 0xRRGGBB.
public func previewCMYK(_ c: Float, _ m: Float, _ y: Float, _ k: Float) -> UInt32 {
    SatzEngine.preview(c: c, m: m, y: y, k: k)
}

/// CMYK of the 0xRRGGBB colour `rgb` in the print condition.
public func separateRGB(_ rgb: UInt32) -> [Float] { SatzEngine.toCmyk(rgb: rgb) }

/// The name and hash of the font `data`.
public func typeface(of data: Data) throws -> Typeface {
    try JSONDecoder().decode(Typeface.self, from: Data(SatzEngine.typeface(bytes: data).utf8))
}

public typealias Inks = SatzEngine.Inks

extension Error {
    /// What went wrong, as the engine words it.
    public var message: String {
        if let e = self as? EngineError, case .Failed(let message) = e { return message }
        return localizedDescription
    }
}
