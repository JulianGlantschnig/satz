import Foundation

/// Finding text in every story; see `web/src/Find.tsx`.
public enum Find {
    /// A match in the story whose first frame is `story`, as a UTF-16 range.
    public struct Match: Equatable, Sendable {
        public var story: String
        public var range: Range<Int>
    }

    /// Every match of `query` in the stories in page order, in whole words or case if
    /// asked, in text of the text style `style` if given.
    public static func matches(_ snapshot: Snapshot, _ query: String, matchCase: Bool = false, words: Bool = false, style: String = "") -> [Match] {
        guard !query.isEmpty else { return [] }
        var pattern = NSRegularExpression.escapedPattern(for: query)
        if words { pattern = #"(?<![\p{L}\p{N}_])"# + pattern + #"(?![\p{L}\p{N}_])"# }
        guard let re = try? NSRegularExpression(pattern: pattern, options: matchCase ? [] : [.caseInsensitive]) else { return [] }
        var heads: [String] = []
        func walk(_ nodes: [Node]) {
            for n in nodes {
                if n.kind == .text, n.story == n.id { heads.append(n.id) }
                walk(n.children ?? [])
            }
        }
        for p in snapshot.pages + snapshot.masters { walk(p.children) }
        return heads.flatMap { story -> [Match] in
            guard let s = snapshot.stories[story] else { return [] }
            let ns = s.text as NSString
            return re.matches(in: s.text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
                if !style.isEmpty {
                    var at = 0
                    let span = s.spans.first { at += $0.len; return at > m.range.location }
                    guard span?.attrs.textStyle == style else { return nil }
                }
                return Match(story: story, range: m.range.location..<m.range.location + m.range.length)
            }
        }
    }
}
