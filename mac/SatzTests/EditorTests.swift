import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct EditorTests {
    @Test func aNewDocumentIsOneA4Page() throws {
        let editor = try SatzDocument().editor.get()
        #expect(editor.snapshot.pages.count == 1)
        #expect(abs(editor.snapshot.pages[0].width - 595.28) < 0.01)
        #expect(editor.pageID == editor.snapshot.pages[0].id)
    }

    @Test func eachEngineStepRegistersOneUndo() throws {
        let editor = try SatzDocument().editor.get()
        let undo = UndoManager()
        undo.groupsByEvent = false
        editor.undoManager = undo

        undo.beginUndoGrouping()
        editor.addPage()
        undo.endUndoGrouping()
        #expect(editor.snapshot.pages.count == 2)
        #expect(undo.canUndo)

        undo.undo()
        #expect(editor.snapshot.pages.count == 1)
        #expect(undo.canRedo)
        undo.redo()
        #expect(editor.snapshot.pages.count == 2)
    }

    @Test func aBatchIsOneUndoStep() throws {
        let editor = try SatzDocument().editor.get()
        let undo = UndoManager()
        undo.groupsByEvent = false
        editor.undoManager = undo

        undo.beginUndoGrouping()
        editor.batch {
            editor.addPage()
            editor.addPage()
        }
        undo.endUndoGrouping()
        #expect(editor.snapshot.pages.count == 3)
        undo.undo()
        #expect(editor.snapshot.pages.count == 1)
    }

    @Test func aRejectedCommandShowsInTheStatusLine() throws {
        let editor = try SatzDocument().editor.get()
        #expect(editor.apply(.deletePage("nope")).isEmpty)
        #expect(editor.status?.error == true)
    }
}
