import AppKit
import SatzCore

extension Story {
    /// The length of the text in UTF-16 code units, as the engine counts.
    var utf16Length: Int { (text as NSString).length }
}

/// Editing text in its frame; see `web/src/textEdit.ts`.
extension Editor {
    /// The story of the thread of the text layer `n`.
    func story(of n: Node) -> Story? { n.story.flatMap { snapshot.stories[$0] } }

    /// The text being edited.
    var editedText: String {
        guard let e = editing, let n = nodes[e.id]?.node else { return "" }
        return story(of: n)?.text ?? ""
    }

    /// Starts editing the text layer `id` with the selection from `anchor` to `focus`,
    /// or all of it.
    func edit(_ id: String, anchor: Int? = nil, focus: Int? = nil) {
        guard let n = nodes[id]?.node, n.kind == .text else { return }
        let length = story(of: n)?.utf16Length ?? 0
        tool = .move
        editing = Editing(id: id, anchor: anchor ?? 0, focus: focus ?? anchor ?? length)
        selection = [id]
        follow()
    }

    /// Replaces the selection with `text` inside the typing undo step and puts the caret after it.
    func insert(_ text: String) {
        guard let e = editing else { return }
        let r = e.range
        if text.isEmpty && r.isEmpty { return }
        beginTyping()
        let length = (text as NSString).length
        apply(.editText(id: e.id, range: r, text: text))
        if editing?.id == e.id || editing != nil {
            editing = Editing(id: editing?.id ?? e.id, anchor: r.lowerBound + length, focus: r.lowerBound + length)
            follow()
        }
    }

    /// Selects from `anchor` to `focus` in the edited text, which ends the typing step.
    func selectText(_ anchor: Int, _ focus: Int) {
        guard let e = editing else { return }
        endTyping()
        editing = Editing(id: e.id, anchor: anchor, focus: focus)
        follow()
    }

    /// Moves the caret to `to`, or the focus when `extend`.
    func moveCaret(to: Int, extend: Bool) {
        guard let e = editing else { return }
        selectText(extend ? e.anchor : to, to)
    }

    /// Leaves the edited text selected, or removes it when it is empty, as Figma does.
    func stopEditing() {
        guard let e = editing else { return }
        endTyping()
        editing = nil
        if let n = nodes[e.id]?.node, n.kind == .text, (story(of: n)?.text ?? "").isEmpty, n.prev == nil, n.next == nil {
            apply(.delete([e.id]))
        }
    }

    /// Moves the edit into the frame of the thread that holds the caret, and to its page.
    func follow() {
        guard let e = editing, let frame = try? engine.textFrame(e.id, index: e.focus), frame != e.id else { return }
        guard let page = (snapshot.pages + snapshot.masters).first(where: { Select.index($0.children, page: $0)[frame] != nil }) else { return }
        if page.id != pageID, !spread.contains(where: { $0.id == page.id }) { pageID = page.id }
        editing = Editing(id: frame, anchor: e.anchor, focus: e.focus)
        selection = [frame]
    }

    // MARK: Keys of the edited text

    /// Moves left or right by a character or word, or to the selection's edge.
    func moveHorizontally(forward: Bool, word: Bool, extend: Bool) {
        guard let e = editing else { return }
        let text = editedText
        let r = e.range
        let to: Int
        if !r.isEmpty && !extend && !word {
            to = forward ? r.upperBound : r.lowerBound
        } else {
            to = forward ? TextEdit.after(text, e.focus, word: word) : TextEdit.before(text, e.focus, word: word)
        }
        moveCaret(to: to, extend: extend)
    }

    /// Moves a line up or down; past the first or last line of a frame into the frame
    /// before or after.
    func moveVertically(up: Bool, extend: Bool) {
        guard let e = editing, let c = try? engine.caret(e.id, index: e.focus), c.count == 3 else { return }
        let length = (editedText as NSString).length
        var to = (try? engine.textIndex(e.id, at: CGPoint(x: c[0], y: up ? c[1] - 0.5 : c[2] + 0.5))) ?? e.focus
        if (try? engine.textLine(e.id, index: to).lowerBound) == (try? engine.textLine(e.id, index: e.focus).lowerBound) {
            let n = nodes[e.id]?.node
            if up {
                to = n?.prev != nil ? max(0, (n?.textStart ?? 0) - 1) : 0
            } else {
                to = n?.next != nil && (n?.textEnd ?? length) < length ? (n?.textEnd ?? length) : length
            }
        }
        moveCaret(to: to, extend: extend)
    }

    /// To the start or end of the line, or of the whole text.
    func moveToLineEdge(end: Bool, all: Bool, extend: Bool) {
        guard let e = editing else { return }
        let range = all ? 0..<(editedText as NSString).length : ((try? engine.textLine(e.id, index: e.focus)) ?? e.focus..<e.focus)
        moveCaret(to: end ? range.upperBound : range.lowerBound, extend: extend)
    }

    /// Deletes the selection, or the character or word before or after the caret.
    func deleteText(forward: Bool, word: Bool) {
        guard let e = editing else { return }
        if e.isCaret {
            let text = editedText
            let to = forward ? TextEdit.after(text, e.focus, word: word) : TextEdit.before(text, e.focus, word: word)
            guard to != e.focus else { return }
            editing = Editing(id: e.id, anchor: e.focus, focus: to)
        }
        insert("")
    }

    /// Tab after `lorem` or `loremN` fills in N words of lorem ipsum.
    func expandLorem() -> Bool {
        guard let e = editing, e.isCaret, let m = TextEdit.loremBefore(e.focus, in: editedText) else { return false }
        editing = Editing(id: e.id, anchor: m.range.lowerBound, focus: m.range.upperBound)
        insert(TextEdit.lorem(m.words))
        return true
    }

    func selectAllText() {
        guard editing != nil else { return }
        selectText(0, (editedText as NSString).length)
    }

    /// The selected text of the edited layer.
    var selectedText: String {
        guard let e = editing else { return "" }
        return (editedText as NSString).substring(with: NSRange(location: e.range.lowerBound, length: e.range.count))
    }

    /// The words of the text `n` that do not fit its thread's last frame.
    func oversetWords(_ n: Node) -> Int {
        guard n.overset == true, let text = story(of: n)?.text, let end = n.textEnd else { return 0 }
        let rest = (text as NSString).substring(from: min(end, (text as NSString).length))
        return rest.split(whereSeparator: \.isWhitespace).count
    }

    /// Threads the text frame `from` on into `to`, as the engine allows.
    func thread(from: String, to: String) {
        let ok = engine.canThread(from: from, to: to)
        apply(.thread(from: from, to: to))
        if ok {
            threading = nil
            select([to])
        }
    }

    /// Shows the match `m`: goes to the page of the frame that holds it and selects it there.
    func reveal(_ m: Find.Match) {
        let frame = (try? engine.textFrame(m.story, index: m.range.lowerBound)) ?? m.story
        if nodes[frame] == nil,
            let page = (snapshot.pages + snapshot.masters).first(where: { Select.index($0.children, page: $0)[frame] != nil })
        {
            showPage(page.id)
        }
        edit(frame, anchor: m.range.lowerBound, focus: m.range.upperBound)
        canvas?.reveal()
    }

    /// Selects the next or previous match of find after the edited text's selection.
    func findStep(_ d: Int) {
        guard !found.isEmpty else { return }
        let story = editing.flatMap { nodes[$0.id]?.node.story }
        let range = editing?.range
        let at = found.firstIndex { $0.story == story && $0.range == range }
        let i = at.map { $0 + d } ?? (d > 0 ? 0 : found.count - 1)
        endTyping()
        reveal(found[(i % found.count + found.count) % found.count])
    }

    func copyText() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(selectedText, forType: .string)
    }
}
