import AppKit
import SatzCore

/// Runs a closure for a menu item, which keeps it as its represented object.
final class MenuAction: NSObject {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    @objc func fire() { run() }

    static func item(_ title: String, enabled: Bool = true, run: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(fire), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        item.isEnabled = enabled
        return item
    }
}

extension CanvasView {
    /// The context menu of what was right-clicked, which it selects first.
    override func menu(for event: NSEvent) -> NSMenu? {
        let p = toSpread(event)
        if editor.tool != .move { editor.tool = .move }
        let id = pick(p, .click)
        if let id, !editor.selection.contains(id) { editor.select([id]) } else if id == nil { editor.select([]) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let some = !editor.selection.isEmpty
        func add(_ title: String.LocalizationValue, enabled: Bool = true, _ run: @escaping () -> Void) {
            menu.addItem(MenuAction.item(String(localized: title), enabled: enabled, run: run))
        }
        add("Cut", enabled: some) { self.editor.cut() }
        add("Copy", enabled: some) { self.editor.copy() }
        add("Paste") { self.editor.paste() }
        add("Duplicate", enabled: some) { self.editor.duplicate(self.editor.selection) }
        add("Delete", enabled: some) { self.editor.delete() }
        menu.addItem(.separator())
        add("Group", enabled: some) { self.editor.group() }
        add("Ungroup", enabled: some) { self.editor.ungroup() }
        add("Use as Mask", enabled: some) { self.editor.mask() }
        menu.addItem(.separator())
        add("Bring to Front", enabled: some) { self.editor.order(.front) }
        add("Bring Forward", enabled: some) { self.editor.order(.forward) }
        add("Send Backward", enabled: some) { self.editor.order(.backward) }
        add("Send to Back", enabled: some) { self.editor.order(.back) }
        menu.addItem(.separator())
        add("Show or Hide", enabled: some) { self.editor.toggle("hidden") }
        add("Lock or Unlock", enabled: some) { self.editor.toggle("locked") }
        add("Zoom to Selection", enabled: some) { self.zoomToSelection() }
        return menu
    }

    /// While a drag nears an edge of the canvas the view scrolls, and the drag goes on
    /// at the pointer as the spread moves under it.
    func autoscroll(for event: NSEvent) {
        let q = convert(event.locationInWindow, from: nil)
        let margin: CGFloat = 24
        let dx: CGFloat = q.x < margin ? margin - q.x : q.x > bounds.width - margin ? bounds.width - margin - q.x : 0
        let dy: CGFloat = q.y < margin ? margin - q.y : q.y > bounds.height - margin ? bounds.height - margin - q.y : 0
        edgeTimer?.invalidate()
        edgeTimer = nil
        guard dx != 0 || dy != 0, drag.map(scrolls) ?? false else { return }
        lastDrag = event
        edgeTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.drag != nil, let last = self.lastDrag else { return }
                let speed: CGFloat = 0.5
                self.show(Viewport(x: self.view.x + dx * speed, y: self.view.y + dy * speed, zoom: self.view.zoom))
                self.dragged(last)
            }
        }
    }

    private func scrolls(_ d: Drag) -> Bool {
        switch d {
        case .pan, .guide: false
        case .move(_, _, let active, _, _): active
        case .draw(_, _, _, let moved, _, _): moved
        default: true
        }
    }
}
