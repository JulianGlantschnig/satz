import AppKit
import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct TextTests {
    /// A new document with an empty text layer being edited.
    func editing() throws -> (Editor, String) {
        let e = try SatzDocument().editor.get()
        let page = try #require(e.pageID)
        let id = e.apply(.create(parent: page, kind: .text, x: 50, y: 50, w: 0, h: 0))[0]
        e.edit(id)
        return (e, id)
    }

    @Test func typingIsOneUndoStepUntilTheCaretMoves() throws {
        let (e, _) = try editing()
        let undo = UndoManager()
        undo.groupsByEvent = false
        e.undoManager = undo
        undo.beginUndoGrouping()
        e.insert("Hello")
        e.insert(" world")
        undo.endUndoGrouping()
        #expect(e.editedText == "Hello world")
        #expect(e.editing?.focus == 11)
        #expect(undo.canUndo)
        undo.undo()
        #expect(e.editedText == "")
    }

    @Test func caretMovesByCharactersAndWords() throws {
        let (e, _) = try editing()
        e.insert("Hello brave world")
        e.moveHorizontally(forward: false, word: true, extend: false)
        #expect(e.editing?.focus == 12)
        e.moveHorizontally(forward: false, word: false, extend: true)
        #expect(e.editing?.anchor == 12 && e.editing?.focus == 11)
        e.moveToLineEdge(end: false, all: true, extend: false)
        #expect(e.editing?.focus == 0)
        e.deleteText(forward: true, word: true)
        #expect(e.editedText == " brave world")
    }

    @Test func loremFillsIn() throws {
        let (e, _) = try editing()
        e.insert("lorem4")
        #expect(e.expandLorem())
        #expect(e.editedText == "Lorem ipsum dolor sit.")
    }

    @Test func anEmptyTextGoesWhenEditingStops() throws {
        let (e, id) = try editing()
        e.stopEditing()
        #expect(e.nodes[id] == nil)
    }

    @Test func selectingAnotherLayerStopsEditing() throws {
        let (e, id) = try editing()
        e.insert("Kept")
        let page = try #require(e.pageID)
        let r = e.apply(.create(parent: page, kind: .rect, x: 0, y: 0, w: 10, h: 10))[0]
        e.select([r])
        #expect(e.editing == nil)
        #expect(e.nodes[id] != nil)
    }
}
