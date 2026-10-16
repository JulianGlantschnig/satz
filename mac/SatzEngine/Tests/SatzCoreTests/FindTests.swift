import Testing

@testable import SatzCore

@MainActor
struct FindTests {
    @Test func findsInEveryStoryByCaseAndWord() throws {
        let e = Engine.blank(width: 300, height: 300, pages: 2, facing: false)
        let s = try e.snapshot
        let a = try e.apply(.create(parent: s.pages[0].id, kind: .text, x: 0, y: 0, w: 0, h: 0))[0]
        let b = try e.apply(.create(parent: s.pages[1].id, kind: .text, x: 0, y: 0, w: 0, h: 0))[0]
        try e.apply(.setText(id: a, text: "Satz setzt Sätze"))
        try e.apply(.setText(id: b, text: "satz, Satzung"))
        let snap = try e.snapshot
        #expect(Find.matches(snap, "satz").map(\.story) == [a, b, b])
        #expect(Find.matches(snap, "Satz", matchCase: true).count == 2)
        #expect(Find.matches(snap, "satz", words: true) == [Find.Match(story: a, range: 0..<4), Find.Match(story: b, range: 0..<4)])
        #expect(Find.matches(snap, "").isEmpty)
    }
}
