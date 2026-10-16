import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// The fonts and images of one engine thread, for painters on any thread. Fonts load
/// on the main actor as the display lists that use them come in; images decode in the
/// background, and `decoded` runs on the main actor once one is ready.
public final class Resources: PaintResources, @unchecked Sendable {
    private let lock = NSLock()
    private var fonts: [UInt32: CGFont] = [:]
    private var sized: [Key: CTFont] = [:]
    private var images: [UInt32: CGImage] = [:]
    /// Images decoding.
    private var pending: Set<UInt32> = []
    /// Images that did not decode.
    private var failed: Set<UInt32> = []
    /// Runs on the main actor when an image has decoded.
    public var decoded: (@MainActor () -> Void)?

    private struct Key: Hashable {
        var id: UInt32
        var size: CGFloat
    }

    public init() {}

    public func font(_ id: UInt32, size: CGFloat) -> CTFont? {
        let id = id & ~DisplayList.missingFont
        return lock.withLock {
            if let f = sized[Key(id: id, size: size)] { return f }
            guard let cg = fonts[id] else { return nil }
            let f = CTFontCreateWithGraphicsFont(cg, size, nil, nil)
            sized[Key(id: id, size: size)] = f
            return f
        }
    }

    public func image(_ id: UInt32) -> CGImage? {
        lock.withLock { images[id] }
    }

    /// Whether some image of the lists is still decoding.
    public var decoding: Bool { lock.withLock { !pending.isEmpty } }

    /// Loads the fonts of `ops` and starts decoding their images.
    @MainActor
    public func prepare(_ ops: [DisplayList.Op]) {
        for op in ops {
            switch op {
            case .glyphRun(let font, _, _, _, _):
                let id = font & ~DisplayList.missingFont
                if lock.withLock({ fonts[id] }) == nil, let f = Self.cgFont(fontBytes(id)) {
                    lock.withLock { fonts[id] = f }
                }
            case .image(let id, _):
                let start = lock.withLock {
                    guard images[id] == nil, !pending.contains(id), !failed.contains(id) else { return false }
                    pending.insert(id)
                    return true
                }
                if start { decode(id) }
            default:
                break
            }
        }
    }

    /// Forgets the images, which show differently after the CMYK profile changed.
    @MainActor
    public func forgetImages() {
        lock.withLock {
            images.removeAll()
            pending.removeAll()
            failed.removeAll()
        }
    }

    @MainActor
    private func decode(_ id: UInt32) {
        // The engine's images live on this thread; the file decodes on any.
        let data = imageBytes(id)
        Task.detached(priority: .userInitiated) { [self] in
            let image = Self.cgImage(data)
            lock.withLock {
                pending.remove(id)
                if let image { images[id] = image } else { failed.insert(id) }
            }
            await MainActor.run { self.decoded?() }
        }
    }

    static func cgFont(_ data: Data) -> CGFont? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGFont(provider)
    }

    static func cgImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}
