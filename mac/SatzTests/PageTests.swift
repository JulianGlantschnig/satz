import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct PageTests {
    func booklet() throws -> Editor {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "examples/booklet.satz")
        return Editor(engine: try .load(Data(contentsOf: url)))
    }

    @Test func deletingKeepsAPageAndShowsTheNext() throws {
        let e = try booklet()
        let ids = e.snapshot.pages.map(\.id)
        e.showPage(ids[2])
        e.deletePages([ids[2], ids[3]])
        #expect(e.snapshot.pages.count == 6)
        #expect(e.pageID == ids[4])
        e.deletePages(e.snapshot.pages.map(\.id))
        #expect(e.snapshot.pages.count == 6)
        #expect(e.status?.error == true)
    }

    @Test func pagesMoveToANewPlace() throws {
        let e = try booklet()
        let ids = e.snapshot.pages.map(\.id)
        e.movePages([ids[7]], to: 0)
        #expect(e.snapshot.pages.first?.id == ids[7])
    }

    @Test func mastersAreMadeAssignedAndLeft() throws {
        let e = try booklet()
        let count = e.snapshot.masters.count
        let page = e.snapshot.pages[1].id
        e.addMaster(like: page, layers: true)
        #expect(e.snapshot.masters.count == count + 1)
        let m = try #require(e.master)
        e.renameMaster(m.id, "Chapter")
        #expect(e.snapshot.masters.last?.name == "Chapter")
        e.useMaster(m.id, on: [page])
        #expect(e.snapshot.pages[1].master == m.id)
        e.exitMaster()
        #expect(e.master == nil)
        #expect(e.pageID == page)
    }

    @Test func aMasterLayerIsOverriddenAndReset() throws {
        let e = try booklet()
        let page = e.snapshot.pages[2]
        let master = try #require(e.snapshot.masters.first { $0.id == page.master })
        let layer = try #require(master.children.last)
        e.showPage(page.id)
        e.override(layer.id, on: page.id)
        let copy = try #require(e.selected.first)
        #expect(copy.overrideOf == layer.id)
        #expect(e.snapshot.page(page.id)?.detached.contains(layer.id) == true)
        e.apply(.resetToMaster([page.id]))
        #expect(e.snapshot.page(page.id)?.detached.isEmpty == true)
    }

    @Test func sectionsGridsAndFacingPages() throws {
        let e = try booklet()
        let page = e.snapshot.pages[3].id
        e.apply(try .setSection(page, Section(start: 10, style: .lowerRoman, prefix: "A-")))
        #expect(e.snapshot.page(page)?.section?.start == 10)
        let grid = SatzCore.Grid(kind: .columns, count: 3, gutter: 10, margin: 30, size: 10)
        e.apply(try .setGrids(page, [grid]))
        #expect(e.snapshot.page(page)?.grids == [grid])
        e.apply(.setDocument(["facingPages": false]))
        #expect(e.snapshot.facingPages == false)
        #expect(e.snapshot.spreads.allSatisfy { $0.count == 1 })
    }

    @Test func formatsByName() {
        let a5 = PageFormat.size("A5", landscape: false)!
        #expect(PageFormat.name(width: a5.width, height: a5.height) == "A5")
        #expect(PageFormat.name(width: a5.height, height: a5.width) == "A5")
        #expect(PageFormat.name(width: 100, height: 100) == nil)
    }
}
