import AppKit
import SatzCore

/// The keys of the canvas without Command; those with it are in the menus.
extension CanvasView {
    override func keyDown(with event: NSEvent) {
        if editor.editing != nil {
            if event.keyCode == 53 && marked == nil {
                editor.stopEditing()
                needsDisplay = true
                return
            }
            inputContext?.handleEvent(event)
            return
        }
        let flags = event.modifierFlags.intersection([.shift, .option, .command, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if editor.pen != nil, [53, 36, 76].contains(event.keyCode) {
            editor.finishPen(closed: false)
            needsDisplay = true
            return
        }
        if var v = editor.vector {
            if [53, 36, 76].contains(event.keyCode) {
                editor.vector = nil
                needsDisplay = true
                return
            }
            if [51, 117].contains(event.keyCode), !v.at.isEmpty {
                editor.deletePicked()
                needsDisplay = true
                return
            }
            if flags.isEmpty, let mode = PathEdit.Mode.allCases.first(where: { $0.key == key }) {
                v.mode = mode
                editor.vector = v
                return
            }
        }
        switch event.keyCode {
        case 49 where flags.isEmpty:  // space
            if !spaceHeld {
                spaceHeld = true
                NSCursor.openHand.set()
            }
        case 51, 117:  // delete, forward delete
            editor.delete()
        case 53:  // escape
            if editor.cropping != nil {
                editor.cropping = nil
            } else if !editor.placing.isEmpty {
                editor.placing = []
            } else if editor.threading != nil {
                editor.threading = nil
            } else if editor.tool != .move {
                editor.tool = .move
            } else {
                editor.escape()
            }
        case 36, 76:  // return, enter
            if editor.cropping != nil {
                editor.cropping = nil
            } else if flags.contains(.shift) {
                editor.selectParent()
            } else if editor.selected.count == 1, let n = editor.selected.first, n.kind == .text {
                editor.edit(n.id)
                wakeCaret()
            } else if editor.selected.count == 1, let n = editor.selected.first, n.kind == .shape, n.ppi == nil {
                editor.editPath(n.id)
            } else {
                editor.enter()
            }
        case 48:  // tab
            editor.selectNext(backwards: flags.contains(.shift))
        case 123...126 where !flags.contains(.command):  // arrows
            let step = flags.contains(.shift) ? 1.0 : 0.1
            let (dx, dy): (Double, Double) = switch event.keyCode {
            case 123: (-step, 0)
            case 124: (step, 0)
            case 125: (0, step)
            default: (0, -step)
            }
            editor.nudge(dx: dx, dy: dy)
        default:
            if flags == .shift && key == "h" {
                editor.flip(vertical: false)
            } else if flags == .shift && key == "v" {
                editor.flip(vertical: true)
            } else if key == "?" {
                editor.showsShortcuts = true
            } else if flags.isEmpty && key == "." {
                editor.toggleOverview()
            } else if flags == .shift && key == "a" {
                editor.addAutoLayout()
            } else if flags == [.shift, .option] && key == "a" {
                editor.removeAutoLayout()
            } else if flags == .shift && key == "w" {
                editor.showsPanels.toggle()
            } else if flags == .shift && key == "g" {
                editor.showsGrids.toggle()
            } else if flags == .shift && (key == "1" || event.keyCode == 18) {
                fit()
            } else if flags == .shift && (key == "2" || event.keyCode == 19) {
                zoomToSelection()
            } else if flags.isEmpty, let tool = Editor.Tool.allCases.first(where: { $0.key == key }) ?? (key == "a" ? .frame : nil) {
                if !event.isARepeat { editor.tool = tool }
            } else {
                super.keyDown(with: event)
            }
        }
        needsDisplay = true
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceHeld = false
            if case .pan = drag {} else { NSCursor.arrow.set() }
        } else {
            super.keyUp(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if drag == nil { track(event) }
    }
}

/// The Edit menu's standard actions reach the canvas through the responder chain, so
/// that text fields keep their own.
extension CanvasView: NSMenuItemValidation {
    @objc func copy(_ sender: Any?) {
        if editor.editing != nil { editor.copyText() } else { editor.copy() }
    }

    @objc func cut(_ sender: Any?) {
        if editor.editing != nil {
            editor.copyText()
            editor.insert("")
        } else {
            editor.cut()
        }
    }

    @objc func paste(_ sender: Any?) {
        if editor.editing != nil {
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            editor.insert(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        } else {
            editor.paste()
        }
    }

    @objc override func selectAll(_ sender: Any?) {
        if editor.editing != nil { editor.selectAllText() } else { editor.selectAll() }
    }

    @objc func delete(_ sender: Any?) {
        if editor.editing != nil { editor.insert("") } else { editor.delete() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)):
            if let e = editor.editing { return !e.isCaret }
            return !editor.selection.isEmpty || (item.action == #selector(delete(_:)) && editor.guide != nil)
        case #selector(paste(_:)):
            return NSPasteboard.general.string(forType: .string) != nil || (editor.editing == nil && Editor.hasImage())
        default:
            return true
        }
    }
}
