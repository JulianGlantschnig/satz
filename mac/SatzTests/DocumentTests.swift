import Foundation
import SatzCore
import Testing

@testable import Satz

@MainActor
struct DocumentTests {
    /// AppKit autosaves on a thread of its own; the engine works only on the main thread.
    @Test func aSaveOffTheMainThreadHoldsTheLatestChange() async throws {
        let document = SatzDocument()
        let e = try document.editor.get()
        let page = try #require(e.pageID)
        let id = e.apply(.create(parent: page, kind: .rect, x: 10, y: 10, w: 20, h: 20))[0]
        let data = try await Task.detached { try document.snapshot(contentType: .satz) }.value
        let copy = try Engine.load(data)
        #expect(try copy.snapshot.pages.first?.children.contains { $0.id == id } == true)
    }
}
