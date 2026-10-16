import Foundation
import Testing

@testable import SatzCore

/// The examples in the repository's `examples/`.
func example(_ name: String) throws -> Data {
    return try Data(contentsOf: root.appending(path: "examples/\(name).satz"))
}

@MainActor
struct EngineTests {
    @Test func theBookletLoadsWithItsPagesAndMasters() throws {
        let e = try Engine.load(example("booklet"))
        let s = try e.snapshot
        #expect(s.pages.count == 8)
        #expect(!s.masters.isEmpty)
        #expect(s.colorMode == .cmyk)
        #expect(s.spreads.first?.count == 1)
        #expect(!s.stories.isEmpty)
    }

    @Test func thePosterLoads() throws {
        let s = try Engine.load(example("poster")).snapshot
        #expect(s.pages.count == 1)
    }

    @Test func aCommandChangesTheSnapshotAndUndoesIt() throws {
        let e = Engine.sample()
        let page = try e.snapshot.pages[0].id
        let made = try e.apply(.duplicatePage(page))
        #expect(made.count == 1)
        #expect(try e.snapshot.pages.count == 2)
        #expect(try e.snapshot.canUndo)
        try e.apply(.undo)
        #expect(try e.snapshot.pages.count == 1)
    }

    @Test func aBadCommandThrowsAndChangesNothing() throws {
        let e = Engine.sample()
        let v = e.version
        #expect(throws: EngineError.self) { try e.apply(.deletePage("nope")) }
        #expect(e.version == v)
    }

    @Test func aSavedDocumentLoadsAgain() throws {
        let e = Engine.blank(width: 595, height: 842, pages: 3, facing: true)
        let again = try Engine.load(e.save())
        #expect(try again.snapshot.pages.count == 3)
        #expect(try again.snapshot.facingPages)
    }

    @Test func createdLayersShowInTheSnapshot() throws {
        let e = Engine.blank(width: 595, height: 842, pages: 1, facing: false)
        let page = try e.snapshot.pages[0].id
        let id = try e.apply(.create(parent: page, kind: .rect, x: 10, y: 20, w: 100, h: 50))[0]
        let node = try #require(try e.snapshot.pages[0].children.first { $0.id == id })
        #expect(node.kind == .shape && node.shape == .rect)
        #expect(node.w == 100)
        try e.apply(.set(id: id, ["name": "Box", "opacity": 0.5]))
        #expect(try e.snapshot.pages[0].children[0].name == "Box")
    }

    @Test func pagesExportAsPdf() throws {
        let e = try Engine.load(example("poster"))
        let pdf = e.pdf(title: "Poster", indices: [0])
        #expect(pdf.starts(with: Data("%PDF".utf8)))
    }
}
