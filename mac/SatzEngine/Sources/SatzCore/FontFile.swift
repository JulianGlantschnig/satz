import CoreText
import Foundation

/// Fonts of this Mac as files the engine takes.
public enum FontFile {
    /// The face `font` as a standalone OpenType file, built from its tables; a face in a
    /// collection (`.ttc`) becomes a file of its own.
    public static func data(of font: CTFont) -> Data? {
        // The array holds the tags themselves, not numbers.
        guard let array = CTFontCopyAvailableTables(font, []) else { return nil }
        let tags = (0..<CFArrayGetCount(array)).map { CTFontTableTag(UInt(bitPattern: CFArrayGetValueAtIndex(array, $0))) }
        guard !tags.isEmpty else { return nil }
        var tables: [(tag: UInt32, data: Data)] = []
        for tag in tags.sorted() {
            guard let d = CTFontCopyTable(font, tag, []) as Data? else { continue }
            tables.append((tag, d))
        }
        let glyf = UInt32(0x676C_7966)  // 'glyf'
        let version: UInt32 = tables.contains { $0.tag == glyf } ? 0x0001_0000 : 0x4F54_544F  // 'OTTO'
        let n = tables.count
        var power = 1
        var log = 0
        while power * 2 <= n {
            power *= 2
            log += 1
        }
        var out = Data()
        func u16(_ v: Int) { out.append(contentsOf: [UInt8(v >> 8 & 0xff), UInt8(v & 0xff)]) }
        func u32(_ v: UInt32) { out.append(contentsOf: [UInt8(v >> 24), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)]) }
        u32(version)
        u16(n)
        u16(power * 16)
        u16(log)
        u16(n * 16 - power * 16)
        var offset = 12 + 16 * n
        for t in tables {
            u32(t.tag)
            u32(checksum(t.data))
            u32(UInt32(offset))
            u32(UInt32(t.data.count))
            offset += (t.data.count + 3) & ~3
        }
        for t in tables {
            out.append(t.data)
            out.append(contentsOf: [UInt8](repeating: 0, count: ((t.data.count + 3) & ~3) - t.data.count))
        }
        return out
    }

    private static func checksum(_ d: Data) -> UInt32 {
        var sum: UInt32 = 0
        d.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
            var i = 0
            while i < p.count {
                var word: UInt32 = 0
                for k in 0..<4 { word = word << 8 | UInt32(i + k < p.count ? p[i + k] : 0) }
                sum = sum &+ word
                i += 4
            }
        }
        return sum
    }

    /// The fonts of this Mac by family, each face with its PostScript and style name.
    public static func families() -> [(family: String, faces: [(postscript: String, style: String)])] {
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        let descriptors = (CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor]) ?? []
        var byFamily: [String: [(String, String)]] = [:]
        for d in descriptors {
            guard let family = CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String,
                let name = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String,
                !family.hasPrefix(".")
            else { continue }
            let style = CTFontDescriptorCopyAttribute(d, kCTFontStyleNameAttribute) as? String ?? ""
            byFamily[family, default: []].append((name, style))
        }
        return byFamily.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { (family: $0, faces: byFamily[$0]!.map { (postscript: $0.0, style: $0.1) }) }
    }
}
