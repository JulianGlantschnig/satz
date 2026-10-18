import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct RasterTests {
    func spread() -> Editor {
        let engine = Engine.blank(width: Units.mm(210), height: Units.mm(297), pages: 3, facing: true)
        return Editor(engine: engine)
    }

    @Test func aRasterIsALockedGroupUnderThePageThatKeepsItsSettings() throws {
        let e = try SatzDocument().editor.get()
        let page = try #require(e.pageID)
        let rect = e.apply(.create(parent: page, kind: .rect, x: 10, y: 10, w: 50, h: 50))[0]
        var spec = RasterGrid.Spec()
        spec.kind = .squares
        spec.punch = .four
        spec.header = true
        spec.headerText = "Physik"
        e.applyRaster(spec, to: .page)
        let children = try #require(e.page?.children)
        #expect(children.count == 2 && children[1].id == rect)
        let raster = children[0]
        #expect(raster.kind == .group && raster.locked && !raster.nonprinting && raster.name == "Raster")
        #expect(raster.raster.flatMap(RasterGrid.Spec.from(json:)) == spec)
        #expect(e.currentRaster == spec)
        // The clipping area with the raster, the holes and the header.
        let area = try #require(raster.children?.first { $0.kind == .frame })
        #expect(area.clip == true && abs(area.x - Units.mm(10)) < 0.01 && !(area.children ?? []).isEmpty)
        #expect(raster.children?.contains { $0.kind == .text } == true)
        #expect(raster.children?.contains { $0.kind == .shape && $0.path != nil } == true)

        // Another raster takes its place, one undo step each.
        spec.prints = false
        e.applyRaster(spec, to: .page)
        let now = try #require(e.page?.children)
        #expect(now.count == 2 && now[0].nonprinting && now[0].id != raster.id)
        e.apply(.undo)
        #expect(e.page?.children.first?.id == raster.id)
        e.removeRaster(from: .page)
        #expect(e.page?.children.map(\.id) == [rect])
    }

    @Test func holesSitAtTheSpineOfEachPageOfASpread() throws {
        let e = spread()
        var spec = RasterGrid.Spec()
        spec.punch = .two
        spec.marginLeft = 20
        spec.marginRight = 10
        e.applyRaster(spec, to: .pages)
        let pages = e.snapshot.pages
        #expect(pages.allSatisfy { $0.children.first?.raster != nil })
        for p in pages {
            let group = try #require(p.children.first)
            let holes = try #require(group.children?.first { $0.kind == .shape })
            let x = holes.x + holes.w / 2
            // The spine is left of a right page and right of a left one.
            if p.side == .left {
                #expect(x > p.width - Units.mm(20))
            } else {
                #expect(x < Units.mm(20))
            }
        }
    }

    @Test func aMasterSpreadGetsARasterOnBothSides() throws {
        let e = spread()
        #expect(e.sheets(.master).isEmpty)
        let master = try #require(e.apply(.addMaster(like: nil)).first)
        for p in e.snapshot.pages { e.apply(.useMaster(page: p.id, master: master)) }
        e.applyRaster(RasterGrid.Spec(), to: .master)
        let rasters = try #require(e.snapshot.page(master)?.children.filter { $0.raster != nil })
        #expect(rasters.count == 2)
        #expect(rasters.contains { $0.x < 0 } && rasters.contains { $0.x >= 0 })
        #expect(e.currentRaster != nil)
    }

    @Test func templatesAreSavedRenamedAndDeleted() {
        let saved = UserDefaults.standard.data(forKey: RasterTemplates.key)
        defer { UserDefaults.standard.set(saved, forKey: RasterTemplates.key) }
        RasterTemplates.own = []
        var spec = RasterGrid.Spec()
        spec.kind = .hex
        RasterTemplates.save("Karte", spec)
        RasterTemplates.save("Karte", spec)
        #expect(RasterTemplates.own.map(\.name) == ["Karte"])
        RasterTemplates.rename("Karte", to: "Hex")
        #expect(RasterTemplates.own.first?.name == "Hex" && RasterTemplates.own.first?.spec.kind == .hex)
        RasterTemplates.delete("Hex")
        #expect(RasterTemplates.own.isEmpty)
        #expect(RasterTemplates.bundled.count == 12)
    }
}
