import Testing

@testable import SatzCore

struct TextEditTests {
    @Test func charactersStepOverSurrogatePairsAndClusters() {
        let t = "a😀b"
        #expect(TextEdit.after(t, 1, word: false) == 3)
        #expect(TextEdit.before(t, 3, word: false) == 1)
        #expect(TextEdit.before(t, 0, word: false) == 0)
        #expect(TextEdit.after(t, 4, word: false) == 4)
    }

    @Test func wordsStepToTheirEnds() {
        let t = "Hello brave world"
        #expect(TextEdit.after(t, 0, word: true) == 5)
        #expect(TextEdit.after(t, 5, word: true) == 11)
        #expect(TextEdit.before(t, 17, word: true) == 12)
        #expect(TextEdit.before(t, 6, word: true) == 0)
        #expect(TextEdit.word(at: 7, in: t) == 6..<11)
    }

    @Test func loremBeforeTheCaret() {
        let t = "Text lorem3"
        let m = TextEdit.loremBefore(11, in: t)
        #expect(m?.range == 5..<11 && m?.words == 3)
        #expect(TextEdit.loremBefore(4, in: t) == nil)
        #expect(TextEdit.lorem(3) == "Lorem ipsum dolor.")
    }
}
