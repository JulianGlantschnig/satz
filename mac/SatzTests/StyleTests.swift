import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct StyleTests {
    @Test func aStyleCopiesOntoOtherLayers() throws {
        let e = try SatzDocument().editor.get()
        let page = try #require(e.pageID)
        let a = e.apply(.create(parent: page, kind: .rect, x: 10, y: 10, w: 50, h: 50))[0]
        let b = e.apply(.create(parent: page, kind: .ellipse, x: 100, y: 10, w: 50, h: 50))[0]
        e.apply(.set(id: a, ["opacity": .number(0.5), "strokeWeight": .number(4)]))
        e.select([a])
        e.copyStyle()
        e.select([b])
        e.pasteStyle()
        let n = try #require(e.nodes[b]?.node)
        #expect(n.opacity == 0.5 && n.strokeWeight == 4)
        #expect(n.fills == e.nodes[a]?.node.fills)
    }

    @Test func flattenTurnsAShapeIntoAPath() throws {
        let e = try SatzDocument().editor.get()
        let page = try #require(e.pageID)
        let a = e.apply(.create(parent: page, kind: .ellipse, x: 10, y: 10, w: 50, h: 50))[0]
        e.select([a])
        e.flatten()
        #expect(e.selected.first?.shape == .path)
    }

    @Test func aOneLineTextFitsItsWidthAndAParagraphItsHeight() throws {
        let e = try SatzDocument().editor.get()
        let page = try #require(e.pageID)
        let t = e.apply(.create(parent: page, kind: .text, x: 10, y: 10, w: 100, h: 40))[0]
        e.apply(.set(id: t, ["sizing": ["horizontal": "fixed", "vertical": "fixed"]]))
        e.apply(.setText(id: t, text: "One line"))
        e.select([t])
        e.fitText()
        #expect(e.selected.first?.sizing == Sizing(horizontal: .hug, vertical: .hug))
        e.fitText(height: true)
        #expect(e.selected.first?.sizing.vertical == .hug)
        #expect(e.selected.first?.sizing.horizontal == .fixed)
    }
}
