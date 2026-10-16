import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct PaintTests {
    @Test func fillsStrokesAndEffectsRoundTripThroughTheEngine() throws {
        let e = try SatzDocument().editor.get()
        let page = try #require(e.pageID)
        let id = e.apply(.create(parent: page, kind: .rect, x: 0, y: 0, w: 50, h: 50))[0]
        let gradient = ColorMath.retype(.solid(.cmyk([0, 1, 1, 0], alpha: 1)), .linear)
        let shadow = EffectList.shadow(.cmyk)
        e.apply(.set(id: id, [
            "fills": try JSON(encoding: [gradient]),
            "strokes": try JSON(encoding: [Fill.solid(.black)]),
            "strokeWeight": 3,
            "effects": try JSON(encoding: [shadow]),
            "blend": "multiply",
        ]))
        #expect(e.status == nil, "\(e.status?.text ?? "")")
        let n = try #require(e.nodes[id]?.node)
        #expect(n.fills.first?.type == .linear)
        #expect(n.fills.first?.stops.count == 2)
        #expect(n.strokeWeight == 3)
        #expect(n.effects.first?.type == .dropShadow)
        #expect(n.blend == .multiply)
    }

    @Test func aSwatchBindsAndResolves() throws {
        let e = try SatzDocument().editor.get()
        let swatch = e.apply(try .addSwatch(name: "Orange", color: .cmyk([0, 0.5, 1, 0], alpha: 1), spot: true))[0]
        let page = try #require(e.pageID)
        let id = e.apply(.create(parent: page, kind: .rect, x: 0, y: 0, w: 50, h: 50))[0]
        e.apply(.set(id: id, ["fills": try JSON(encoding: [Fill.solid(.swatch(swatch, tint: 0.5, alpha: 1))])]))
        let c = try #require(e.nodes[id]?.node.fills.first?.color)
        guard case .cmyk(let k, _) = ColorMath.resolve(c, Scope(e.snapshot)) else { Issue.record("not CMYK"); return }
        #expect(abs(k[2] - 0.5) < 1e-6)
    }
}
