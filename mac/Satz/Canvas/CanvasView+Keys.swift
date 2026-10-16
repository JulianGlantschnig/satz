import AppKit
import SatzCore

/// The keys of the canvas without Command; those with it are in the menus.
extension CanvasView {
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.shift, .option, .command, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch event.keyCode {
        case 49 where flags.isEmpty:  // space
            if !spaceHeld {
                spaceHeld = true
                NSCursor.openHand.set()
            }
        case 51, 117:  // delete, forward delete
            editor.delete()
        case 53:  // escape
            editor.escape()
        case 36, 76:  // return, enter
            if flags.contains(.shift) { editor.selectParent() } else { editor.enter() }
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
    @objc func copy(_ sender: Any?) { editor.copy() }
    @objc func cut(_ sender: Any?) { editor.cut() }
    @objc func paste(_ sender: Any?) { editor.paste() }
    @objc override func selectAll(_ sender: Any?) { editor.selectAll() }
    @objc func delete(_ sender: Any?) { editor.delete() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)):
            return !editor.selection.isEmpty || (item.action == #selector(delete(_:)) && editor.guide != nil)
        case #selector(paste(_:)):
            return NSPasteboard.general.string(forType: .string) != nil
        default:
            return true
        }
    }
}
