import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct PathTests {
    func editor() throws -> (Editor, page: Page) {
        let e = try SatzDocument().editor.get()
        return (e, try #require(e.page))
    }

    @Test func thePenDrawsAPathThatClosesOnItsFirstAnchorInOneUndoStep() throws {
        let (e, page) = try editor()
        let undo = UndoManager()
        e.undoManager = undo
        e.tool = .pen
        e.startPen(at: CGPoint(x: 100, y: 100), parent: page.id, dx: 0)
        let id = try #require(e.pen?.id)
        e.setPen(e.pen!.anchors + [Vector.Anchor(x: 200, y: 100)])
        e.setPen(e.pen!.anchors + [Vector.Anchor(x: 150, y: 200, hx: 20, hy: 0)])
        e.finishPen(closed: true)
        #expect(e.pen == nil)
        #expect(e.tool == .move)
        #expect(e.selection == [id])
        let n = try #require(e.nodes[id]?.node)
        #expect(n.shape == .path)
        #expect(n.path?.last == 5)
        #expect(abs(n.x - 100) < 0.1 && abs(n.w - 100) < 0.5)
        undo.undo()
        #expect(e.nodes[id] == nil)
    }

    @Test func aPenPathOfOneAnchorGoes() throws {
        let (e, page) = try editor()
        e.tool = .pen
        e.startPen(at: CGPoint(x: 100, y: 100), parent: page.id, dx: 0)
        let id = try #require(e.pen?.id)
        e.tool = .move
        #expect(e.pen == nil)
        #expect(e.nodes[id] == nil)
    }

    @Test func aRectangleBecomesAPathWhosePointsMoveAndGo() throws {
        let (e, page) = try editor()
        let id = e.apply(.create(parent: page.id, kind: .rect, x: Units.mm(10), y: Units.mm(10), w: Units.mm(40), h: Units.mm(20)))[0]
        e.editPath(id)
        #expect(e.vector?.id == id)
        let cs = e.knots()
        #expect(cs.count == 1 && cs[0].knots.count == 4 && cs[0].closed)
        #expect(abs(cs[0].knots[0].x - Units.mm(10)) < 0.1)
        // The second point moves right, which widens the path.
        e.setKnots(Vector.shift(cs, [Vector.At(0, 1)], .point, Units.mm(10), 0), at: [Vector.At(0, 1)])
        #expect(abs(try #require(e.nodes[id]?.node).w - Units.mm(50)) < 0.2)
        e.smoothPicked(true)
        #expect(e.knots()[0].knots[1].curved)
        e.deletePicked()
        #expect(e.knots()[0].knots.count == 3)
        #expect(e.vector?.at.isEmpty == true)
        // A click elsewhere in the selection ends the edit.
        e.select([])
        #expect(e.vector == nil)
    }
}
