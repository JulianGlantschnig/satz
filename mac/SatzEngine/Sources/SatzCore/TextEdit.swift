import Foundation

/// A text layer being edited in its frame; `anchor` and `focus` are UTF-16 indices,
/// as the engine counts.
public struct Editing: Equatable, Sendable {
    public var id: String
    public var anchor: Int
    public var focus: Int

    public init(id: String, anchor: Int, focus: Int) {
        self.id = id
        self.anchor = anchor
        self.focus = focus
    }

    public var range: Range<Int> { min(anchor, focus)..<max(anchor, focus) }
    public var isCaret: Bool { anchor == focus }
}

/// Moving through text by characters and words; see `web/src/textEdit.ts`.
public enum TextEdit {
    /// Stands for the number of the page a text is on, as InDesign's Current Page Number.
    public static let pageNumber = "\u{18}"

    /// The words of `text` as UTF-16 ranges.
    static func words(_ text: String) -> [Range<Int>] {
        let ns = text as NSString
        var out: [Range<Int>] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .localized]) { _, r, _, _ in
            out.append(r.location..<r.location + r.length)
        }
        return out
    }

    /// The character boundary before `i`, or the start of the word before it.
    public static func before(_ text: String, _ i: Int, word: Bool) -> Int {
        if word { return words(text).last { $0.lowerBound < i }?.lowerBound ?? 0 }
        guard i > 0 else { return 0 }
        let ns = text as NSString
        return ns.rangeOfComposedCharacterSequence(at: i - 1).location
    }

    /// The character boundary after `i`, or the end of the word after it.
    public static func after(_ text: String, _ i: Int, word: Bool) -> Int {
        let ns = text as NSString
        if word { return words(text).first { $0.upperBound > i }?.upperBound ?? ns.length }
        guard i < ns.length else { return ns.length }
        let r = ns.rangeOfComposedCharacterSequence(at: i)
        return r.location + r.length
    }

    /// The word around `i`, for a double click.
    public static func word(at i: Int, in text: String) -> Range<Int> {
        words(text).first { $0.lowerBound <= i && i < $0.upperBound } ?? i..<i
    }

    /// The paragraph around `i`, for a triple click.
    public static func paragraph(at i: Int, in text: String) -> Range<Int> {
        let ns = text as NSString
        let r = ns.paragraphRange(for: NSRange(location: min(i, ns.length), length: 0))
        return r.location..<r.location + r.length
    }

    private static let lorem = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat".split(separator: " ")

    /// `n` words of lorem ipsum as a sentence.
    public static func lorem(_ n: Int) -> String {
        let words = (0..<n).map { lorem[$0 % lorem.count] }.joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst() + "."
    }

    /// The word `lorem` or `loremN` just before `i`, which Tab turns into N words (10 by default).
    public static func loremBefore(_ i: Int, in text: String) -> (range: Range<Int>, words: Int)? {
        let head = (text as NSString).substring(to: i)
        guard let m = head.range(of: #"\blorem(\d*)$"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let word = String(head[m])
        let digits = word.dropFirst(5)
        let n = min(Int(digits) ?? 10, 10000)
        let length = (word as NSString).length
        return (i - length..<i, n)
    }
}
