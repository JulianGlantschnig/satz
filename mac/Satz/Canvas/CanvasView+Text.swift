import AppKit
import SatzCore

/// Typing into the edited text through the Mac's text input: keys, dead keys, input
/// methods and dictation, and the standard text commands for moving and deleting.
extension CanvasView: NSTextInputClient {
    // MARK: Input

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard editor.editing != nil else { return }
        marked = nil
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        editor.insert(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        wakeCaret()
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        marked = text.isEmpty ? nil : text
        needsDisplay = true
    }

    func unmarkText() {
        marked = nil
        needsDisplay = true
    }

    func selectedRange() -> NSRange {
        guard let e = editor.editing else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: e.range.lowerBound, length: e.range.count)
    }

    func markedRange() -> NSRange {
        guard let marked, let e = editor.editing else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: e.range.lowerBound, length: (marked as NSString).length)
    }

    func hasMarkedText() -> Bool { marked != nil }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let text = editor.editedText as NSString
        let r = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        actualRange?.pointee = r
        return NSAttributedString(string: text.substring(with: r))
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    /// The caret on screen, for the input method's candidate window.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let e = editor.editing, let c = try? editor.engine.caret(e.id, index: range.location), c.count == 3, let n = editor.nodes[e.id]?.node else {
            return .zero
        }
        let dx = editor.dx(n.id)
        let top = view.toCanvas(CGPoint(x: c[0] + dx, y: c[1]))
        let bottom = view.toCanvas(CGPoint(x: c[0] + dx, y: c[2]))
        let local = CGRect(x: top.x, y: top.y, width: 1, height: bottom.y - top.y)
        return window?.convertToScreen(convert(local, to: nil)) ?? .zero
    }

    func characterIndex(for point: NSPoint) -> Int {
        guard let e = editor.editing, let window else { return NSNotFound }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        return (try? editor.engine.textIndex(e.id, at: editor.local(e.id, view.toSpread(local)))) ?? NSNotFound
    }

    // MARK: Text commands

    override func doCommand(by selector: Selector) {
        let handled = textCommand(selector)
        if !handled { super.doCommand(by: selector) }
        wakeCaret()
        needsDisplay = true
    }

    /// Runs the text command `selector` on the edited text; false when it is not one.
    private func textCommand(_ selector: Selector) -> Bool {
        let e = editor
        switch NSStringFromSelector(selector) {
        case "moveLeft:": e.moveHorizontally(forward: false, word: false, extend: false)
        case "moveRight:": e.moveHorizontally(forward: true, word: false, extend: false)
        case "moveLeftAndModifySelection:", "moveBackwardAndModifySelection:": e.moveHorizontally(forward: false, word: false, extend: true)
        case "moveRightAndModifySelection:", "moveForwardAndModifySelection:": e.moveHorizontally(forward: true, word: false, extend: true)
        case "moveWordLeft:", "moveWordBackward:": e.moveHorizontally(forward: false, word: true, extend: false)
        case "moveWordRight:", "moveWordForward:": e.moveHorizontally(forward: true, word: true, extend: false)
        case "moveWordLeftAndModifySelection:", "moveWordBackwardAndModifySelection:": e.moveHorizontally(forward: false, word: true, extend: true)
        case "moveWordRightAndModifySelection:", "moveWordForwardAndModifySelection:": e.moveHorizontally(forward: true, word: true, extend: true)
        case "moveUp:": e.moveVertically(up: true, extend: false)
        case "moveDown:": e.moveVertically(up: false, extend: false)
        case "moveUpAndModifySelection:": e.moveVertically(up: true, extend: true)
        case "moveDownAndModifySelection:": e.moveVertically(up: false, extend: true)
        case "moveToBeginningOfLine:", "moveToLeftEndOfLine:": e.moveToLineEdge(end: false, all: false, extend: false)
        case "moveToEndOfLine:", "moveToRightEndOfLine:": e.moveToLineEdge(end: true, all: false, extend: false)
        case "moveToBeginningOfLineAndModifySelection:", "moveToLeftEndOfLineAndModifySelection:": e.moveToLineEdge(end: false, all: false, extend: true)
        case "moveToEndOfLineAndModifySelection:", "moveToRightEndOfLineAndModifySelection:": e.moveToLineEdge(end: true, all: false, extend: true)
        case "moveToBeginningOfDocument:", "moveToBeginningOfParagraph:": e.moveToLineEdge(end: false, all: true, extend: false)
        case "moveToEndOfDocument:", "moveToEndOfParagraph:": e.moveToLineEdge(end: true, all: true, extend: false)
        case "moveToBeginningOfDocumentAndModifySelection:": e.moveToLineEdge(end: false, all: true, extend: true)
        case "moveToEndOfDocumentAndModifySelection:": e.moveToLineEdge(end: true, all: true, extend: true)
        case "deleteBackward:", "deleteBackwardByDecomposingPreviousCharacter:": e.deleteText(forward: false, word: false)
        case "deleteForward:": e.deleteText(forward: true, word: false)
        case "deleteWordBackward:": e.deleteText(forward: false, word: true)
        case "deleteWordForward:": e.deleteText(forward: true, word: true)
        case "deleteToBeginningOfLine:":
            e.moveToLineEdge(end: false, all: false, extend: true)
            e.insert("")
        case "insertNewline:", "insertLineBreak:", "insertParagraphSeparator:", "insertNewlineIgnoringFieldEditor:": e.insert("\n")
        case "insertTab:":
            if !e.expandLorem() { e.insert("\t") }
        case "cancelOperation:": e.stopEditing()
        case "selectAll:": e.selectAllText()
        default: return false
        }
        return true
    }

    // MARK: Mouse in the edited text

    /// The frame of the edited text's thread on the spread that `p` is inside.
    func inEdited(_ p: CGPoint) -> Node? {
        guard let e = editor.editing, let n = editor.nodes[e.id]?.node, n.kind == .text else { return nil }
        func inside(_ f: Node) -> Bool {
            guard f.kind == .text, f.story == n.story else { return false }
            return editor.shown(f).contains(Handles.spin(p, -editor.shown(f).rotation, around: editor.shown(f).center))
        }
        if inside(n) { return n }
        return editor.nodes.values.map(\.node).first(where: inside)
    }

    /// The index in the text `id` nearest `p` on the spread.
    func textIndex(_ id: String, at p: CGPoint) -> Int {
        (try? editor.engine.textIndex(id, at: editor.local(id, p))) ?? 0
    }

    // MARK: Caret

    /// Shows the caret and blinks it from now on, so that it stays while typing.
    func wakeCaret() {
        caretOn = true
        blink?.invalidate()
        blink = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.editor.editing != nil else { return }
                self.caretOn.toggle()
                self.needsDisplay = true
            }
        }
        needsDisplay = true
    }

    /// The caret or selection of the edited text, and the text an input method composes.
    func drawEditedText(_ ctx: CGContext) {
        guard let e = editor.editing else { return }
        let pages = editor.master.map { [$0] } ?? editor.spread
        for page in pages {
            let caretWidth = Float(1 / view.zoom)
            let showsCaret = !e.isCaret || caretOn
            guard showsCaret,
                let data = try? editor.engine.textOverlay(e.id, anchor: e.anchor, focus: e.focus, caretWidth: caretWidth, page: page.id),
                let ops = try? DisplayList.decode(data)
            else { continue }
            ctx.saveGState()
            ctx.translateBy(x: view.x + page.x * view.zoom, y: view.y)
            ctx.scaleBy(x: view.zoom, y: view.zoom)
            painter.draw(ops, in: ctx)
            ctx.restoreGState()
        }
        if let marked, let c = try? editor.engine.caret(e.id, index: e.focus), c.count == 3 {
            let dx = editor.dx(e.id)
            let at = view.toCanvas(CGPoint(x: c[0] + dx, y: c[2]))
            let text = NSAttributedString(string: marked, attributes: [
                .font: NSFont.systemFont(ofSize: max(11, (c[2] - c[1]) * view.zoom * 0.7)),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .backgroundColor: NSColor.textBackgroundColor,
            ])
            NSGraphicsContext.saveGraphicsState()
            text.draw(at: CGPoint(x: at.x, y: at.y - text.size().height))
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
