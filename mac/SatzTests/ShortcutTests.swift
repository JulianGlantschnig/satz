import AppKit
import Testing

@testable import Satz

@MainActor
struct ShortcutTests {
    @Test func keysReadAsTheMenusShowThem() {
        #expect(Shortcut.name(key: "k", modifiers: [.command, .shift]) == "⇧⌘K")
        #expect(Shortcut.name(key: "\r", modifiers: [.control, .option]) == "⌃⌥↩")
        #expect(Shortcut.name(key: "", modifiers: .command) == "")
    }

    @Test func userKeyEquivalentsGoBothWays() {
        let e = Shortcut.equivalent(key: "J", modifiers: [.command, .control, .shift])
        #expect(e == "^$@j")
        let (key, modifiers) = Shortcut.parse(e)
        #expect(key == "j")
        #expect(modifiers == [.command, .control, .shift])
        // A key that is itself a modifier sign stays the key.
        #expect(Shortcut.parse("@$").key == "$")
    }

    @Test func theMenusListTheirCommandsWithPaths() {
        let item = NSMenuItem(title: "Fill Frame", action: #selector(NSText.selectAll(_:)), keyEquivalent: "f")
        item.keyEquivalentModifierMask = [.command, .option]
        let sub = NSMenu(title: "Fit Image")
        sub.addItem(item)
        let fit = NSMenuItem(title: "Fit Image", action: nil, keyEquivalent: "")
        fit.submenu = sub
        let object = NSMenu(title: "Object")
        object.addItem(fit)
        let top = NSMenuItem(title: "Object", action: nil, keyEquivalent: "")
        top.submenu = object
        let main = NSMenu()
        main.addItem(top)
        let before = NSApp.mainMenu
        NSApp.mainMenu = main
        defer { NSApp.mainMenu = before }
        let all = MenuCommand.all()
        #expect(all.map(\.id) == ["Object ▸ Fit Image ▸ Fill Frame"])
        #expect(all.first?.shortcut == "⌥⌘F")
    }
}
