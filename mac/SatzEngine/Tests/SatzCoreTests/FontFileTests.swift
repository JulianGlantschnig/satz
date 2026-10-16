import CoreText
import Foundation
import Testing

@testable import SatzCore

@MainActor
struct FontFileTests {
    @Test func aFaceOfACollectionBecomesAFontTheEngineTakes() throws {
        // Helvetica ships as a collection.
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil)
        let data = try #require(FontFile.data(of: font))
        let face = try typeface(of: data)
        #expect(face.family == "Helvetica")
        #expect(face.style == "Bold")
        let e = Engine.blank(width: 100, height: 100, pages: 1, facing: false)
        let added = try e.addFont(data)
        #expect(try e.snapshot.fonts.contains(added))
    }

    @Test func theMacsFontsListByFamily() {
        let families = FontFile.families()
        #expect(families.contains { $0.family == "Helvetica" && $0.faces.contains { $0.postscript == "Helvetica" } })
    }
}
