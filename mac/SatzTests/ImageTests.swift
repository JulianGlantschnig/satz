import AppKit
import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct ImageTests {
    static let earthrise = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "examples/earthrise.jpg")

    /// A new A4 document with the earthrise placed amid its page.
    func placed() throws -> (Editor, Node) {
        let e = try SatzDocument().editor.get()
        let page = try #require(e.page)
        #expect(e.loadImage(try Data(contentsOf: Self.earthrise), name: "earthrise.jpg"))
        let waiting = try #require(e.placing.first)
        #expect(waiting.image != nil)
        e.place(at: CGPoint(x: page.width / 2, y: page.height / 2), parent: page.id, dx: 0)
        #expect(e.placing.isEmpty)
        return (e, try #require(e.selectedImage))
    }

    @Test func anImagePlacesAt300PpiOrToFitThePage() throws {
        let (e, n) = try placed()
        let page = try #require(e.page)
        #expect(n.name == "earthrise.jpg")
        #expect(n.w <= page.width + 1e-6 && n.h <= page.height + 1e-6)
        #expect(try #require(n.ppi) >= 299)
        #expect(abs(n.x + n.w / 2 - page.width / 2) < 0.1)
        #expect(Editor.fit(of: n.fills) == .frame)
    }

    @Test func fitsAndAdjustmentsChangeTheImageFill() throws {
        let (e, n) = try placed()
        e.apply(.setFrame(id: n.id, x: n.x, y: n.y, w: n.w, h: n.w / 2))
        e.fitImage(.contain)
        #expect(Editor.fit(of: try #require(e.selectedImage).fills) == .contain)
        e.fitImage(.cover)
        let covered = try #require(e.selectedImage)
        #expect(Editor.fit(of: covered.fills) == .cover)
        // The square image is taller than the wide frame and centred on it.
        let box = try #require(Editor.imageBox(covered, in: e.placed(covered)))
        #expect(box.h > covered.h)
        #expect(abs(box.y + box.h / 2 - (covered.y + covered.h / 2)) < 0.01)
        e.adjust(covered, [0.2, -0.1, 0.5])
        #expect(e.selectedImage?.fills.first { $0.type == .image }?.adjust == [0.2, -0.1, 0.5])
    }

    @Test func croppingMovesTheImageInsideItsFrameUntilTheSelectionGoes() throws {
        let (e, n) = try placed()
        e.toggleCrop()
        #expect(e.cropping == n.id)
        e.moveImage(n, by: CGPoint(x: n.w / 4, y: 0))
        let moved = try #require(e.selectedImage)
        #expect(abs(try #require(Editor.imageBox(moved, in: e.placed(moved))).x - (n.x + n.w / 4)) < 0.01)
        #expect(Editor.fit(of: moved.fills) == nil)
        e.tool = .rect
        #expect(e.cropping == nil)
        e.tool = .move
        e.select([n.id])
        e.toggleCrop()
        e.select([])
        #expect(e.cropping == nil)
    }

    @Test func imagesComeOffThePasteboardButOtherFilesDoNot() throws {
        let pb = NSPasteboard(name: .init("satz-test-\(UUID())"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.writeObjects([Self.earthrise as NSURL])
        #expect(Editor.hasImage(pb))
        #expect(Editor.pastedImage(pb)?.name == "earthrise.jpg")
        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: #filePath) as NSURL])
        #expect(!Editor.hasImage(pb))
        pb.clearContents()
        let tiff = try #require(NSImage(contentsOf: Self.earthrise)?.tiffRepresentation)
        pb.setData(tiff, forType: .tiff)
        let png = try #require(Editor.pastedImage(pb)?.data)
        #expect(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func aBadFileSaysWhyItDoesNotPlace() throws {
        let e = try SatzDocument().editor.get()
        #expect(!e.loadImage(Data("no image".utf8), name: "x.png"))
        #expect(e.status?.error == true)
        #expect(e.placing.isEmpty)
    }
}
