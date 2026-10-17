import CoreGraphics
import Foundation
import ImageIO
import SatzEngine
import UniformTypeIdentifiers

/// A document as an export takes it off the main actor: its saved bytes and the fonts
/// added to it, which the engine keeps per thread.
public struct DocumentCopy: Sendable {
    public var bytes: Data
    public var fonts: [Data]

    public init(bytes: Data, fonts: [Data] = []) {
        self.bytes = bytes
        self.fonts = fonts
    }

    /// The document in an engine of the calling thread, which must use it only there.
    nonisolated func core() throws -> Core {
        // Fonts go first, so that the text is set in them as it loads.
        let core = try Core.load(bytes: bytes)
        for font in fonts { _ = try? core.addFont(bytes: font) }
        return core
    }
}

extension Engine {
    /// The document and its added fonts, for an export on another thread.
    public func copy() -> DocumentCopy {
        let fonts = (1..<max(1, fontsAdded())).map { fontBytes(UInt32($0)) }.filter { !$0.isEmpty }
        return DocumentCopy(bytes: save(), fonts: fonts)
    }
}

/// The files Satz exports. Each export runs on the calling thread, which it may block
/// for a while, in an engine of its own.
public enum Export {
    public enum Format: String, CaseIterable, Sendable, Identifiable {
        case pdf, png, jpeg, zip

        public var id: String { rawValue }

        public var fileExtension: String {
            switch self {
            case .pdf: "pdf"
            case .png: "png"
            case .jpeg: "jpg"
            case .zip: "zip"
            }
        }

        public var type: UTType {
            switch self {
            case .pdf: .pdf
            case .png: .png
            case .jpeg: .jpeg
            case .zip: .zip
            }
        }

        /// One file per page rather than one for all.
        public var perPage: Bool { self == .png || self == .jpeg }
    }

    /// The pages at `indices` of `copy` as `format`: one PDF or package titled `title`,
    /// or an image of each page at `ppi`. `preset` overrides the document's for a PDF.
    public nonisolated static func files(
        _ copy: DocumentCopy, format: Format, indices: [Int], title: String, ppi: Double, preset: Preset? = nil,
        date: Date = Date()
    ) throws -> [Data] {
        let core = try copy.core()
        if let preset {
            _ = try core.apply(command: Command.setDocument(["preset": .string(preset.rawValue)]).json)
        }
        let chosen = indices.map { UInt32($0) }
        let iso = date.ISO8601Format(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.colon))
        switch format {
        case .pdf:
            return [core.pdf(title: title, date: iso, indices: chosen)]
        case .zip:
            return [core.package(title: title, date: iso, indices: chosen)]
        case .png, .jpeg:
            let snapshot = try Snapshot.decode(core.snapshot())
            return try indices.map { i in
                guard snapshot.pages.indices.contains(i), let png = core.png(page: snapshot.pages[i].id, ppi: Float(ppi)) else {
                    throw EngineError.Failed(message: "There is no page \(i + 1)")
                }
                return format == .png ? png : try jpeg(of: png, quality: 0.9)
            }
        }
    }

    /// The PNG `png` as a JPEG of `quality` in 0...1, with its resolution.
    public nonisolated static func jpeg(of png: Data, quality: Double) throws -> Data {
        let out = NSMutableData()
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw EngineError.Failed(message: "The image does not convert to JPEG") }
        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImageFromSource(dest, source, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw EngineError.Failed(message: "The image does not convert to JPEG") }
        return out as Data
    }

    /// The indices of the pages that `text` names, as `1-3, 5`, all of `count` when it
    /// is empty; nil when it names a page that is not there.
    public nonisolated static func pages(_ text: String, count: Int) -> [Int]? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return Array(0..<count) }
        var out = Set<Int>()
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let ends = part.split(whereSeparator: { $0 == "-" || $0 == "–" }).map { $0.trimmingCharacters(in: .whitespaces) }
            guard (1...2).contains(ends.count), let a = Int(ends[0]), let b = Int(ends.last!),
                part.filter({ $0 == "-" || $0 == "–" }).count == ends.count - 1,
                a >= 1, b <= count, a <= b
            else { return nil }
            out.formUnion((a - 1)..<b)
        }
        return out.sorted()
    }
}
