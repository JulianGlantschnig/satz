import AppKit
import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct LayerTests {
    /// A new document with two rectangles on its page.
    func editor() throws -> (Editor, page: String, a: String, b: String) {
        let e = try SatzDocument().editor.get()
        let page = try #require(e.pageID)
        let a = e.apply(.create(parent: page, kind: .rect, x: Units.mm(10), y: Units.mm(10), w: Units.mm(20), h: Units.mm(20)))[0]
        let b = e.apply(.create(parent: page, kind: .rect, x: Units.mm(50), y: Units.mm(10), w: Units.mm(20), h: Units.mm(20)))[0]
        return (e, page, a, b)
    }

    @Test func framesRoundToTenthsOfAMillimetre() throws {
        let (e, _, a, _) = try editor()
        e.apply(.setFrame(id: a, x: Units.mm(12.3456), y: 7.123456, w: Units.mm(20.004), h: Units.mm(20)))
        let n = try #require(e.nodes[a]?.node)
        #expect(abs(n.x / Units.ptPerMM - 12.3) < 1e-9)
        #expect(abs(n.w / Units.ptPerMM - 20) < 1e-9)
    }

    @Test func nudgingMovesTheSelectionInOneUndoStep() throws {
        let (e, _, a, b) = try editor()
        let undo = UndoManager()
        undo.groupsByEvent = false
        e.undoManager = undo
        e.select([a, b])
        undo.beginUndoGrouping()
        e.nudge(dx: 1, dy: 0)
        undo.endUndoGrouping()
        #expect(abs(try #require(e.nodes[a]?.node).x / Units.ptPerMM - 11) < 1e-9)
        #expect(abs(try #require(e.nodes[b]?.node).x / Units.ptPerMM - 51) < 1e-9)
        undo.undo()
        #expect(abs(try #require(e.nodes[a]?.node).x / Units.ptPerMM - 10) < 1e-9)
    }

    @Test func duplicatingAgainStepsAsFarAsTheCopiesWereMoved() throws {
        let (e, _, a, _) = try editor()
        e.duplicate([a])
        let first = e.selection
        #expect(first.count == 1 && first[0] != a)
        e.nudge(dx: 5, dy: 0)
        e.duplicate(first)
        let second = try #require(e.selected.first)
        #expect(abs(second.x / Units.ptPerMM - 20) < 1e-9)
    }

    @Test func groupingAndUngroupingKeepTheLayers() throws {
        let (e, page, a, b) = try editor()
        e.select([a, b])
        e.group()
        let g = try #require(e.selection.first)
        #expect(e.nodes[g]?.node.kind == .group)
        #expect(e.nodes[a]?.parent?.id == g)
        e.escape()
        #expect(e.selection.isEmpty)
        e.select([a])
        e.escape()
        #expect(e.selection == [g])
        e.ungroup()
        #expect(e.nodes[a]?.parent == nil && e.nodes[a]?.page?.id == page)
    }

    @Test func copyAndPasteMakeNewLayers() throws {
        let (e, _, a, _) = try editor()
        e.select([a])
        e.copy()
        #expect(NSPasteboard.general.string(forType: .string) == e.nodes[a]?.node.name)
        e.paste()
        #expect(e.selection.count == 1 && e.selection[0] != a)
        let count = e.page?.children.count
        e.select([a])
        e.cut()
        #expect(e.page?.children.count == (count ?? 0) - 1)
    }

    @Test func pastedTextBecomesATextLayer() throws {
        let (e, _, _, _) = try editor()
        e.pasteText("Hello")
        let n = try #require(e.selected.first)
        #expect(n.kind == .text)
        #expect(e.snapshot.stories[n.story ?? ""]?.text == "Hello")
    }

    @Test func hidingAndLockingToggle() throws {
        let (e, _, a, b) = try editor()
        e.select([a, b])
        e.toggle("hidden")
        #expect(e.selected.allSatisfy { $0.hidden })
        e.toggle("hidden")
        #expect(e.selected.allSatisfy { !$0.hidden })
        e.toggle("locked")
        #expect(e.selected.allSatisfy { $0.locked })
    }

    @Test func turningALayerTurnsItAroundTheCentre() throws {
        let (e, _, a, _) = try editor()
        let n = try #require(e.nodes[a]?.node)
        let c = e.placed(n).center
        e.turn([n], by: 90, around: c)
        let t = try #require(e.nodes[a]?.node)
        #expect(abs(t.rotation - 90) < 1e-9)
        let shown = e.shown(t)
        #expect(abs(shown.center.x - c.x) < 0.01 && abs(shown.center.y - c.y) < 0.01)
        #expect(abs(shown.rotation - 90) < 1e-6)
    }

    @Test func tabWalksTheLayersAndSelectAllTakesThePage() throws {
        let (e, _, a, b) = try editor()
        e.selectAll()
        #expect(Set(e.selection) == [a, b])
        e.select([b])
        e.selectNext(backwards: false)
        #expect(e.selection == [a])
    }

    @Test func deletingAPickedGuideRemovesIt() throws {
        let (e, page, _, _) = try editor()
        e.apply(try .setGuides(page, Guides(x: [100, 200], y: [])))
        e.guide = Editor.PickedGuide(page: page, axis: .x, index: 0)
        e.delete()
        #expect(e.snapshot.page(page)?.guides.x == [200])
        #expect(e.guide == nil)
    }
}
