import AppKit
import SwiftUI

/// A command of the menu bar, for the command palette and the shortcuts; the menus are
/// the one list of what Satz does.
struct MenuCommand: Identifiable {
    /// The menus down to the item, such as "Object ▸ Fit Image ▸ Fill Frame".
    var id: String { (path + [title]).joined(separator: " ▸ ") }
    var title: String
    var path: [String]
    var shortcut: String
    var enabled: Bool
    weak var item: NSMenuItem?

    /// Runs the command as its menu item would.
    func run() {
        guard let item, let menu = item.menu else { return }
        let i = menu.index(of: item)
        if i >= 0 { menu.performActionForItem(at: i) }
    }

    /// The commands of the main menu, without the window list, Services and the like.
    static func all() -> [MenuCommand] {
        guard let main = NSApp.mainMenu else { return [] }
        main.update()
        var out: [MenuCommand] = []
        func walk(_ menu: NSMenu, _ path: [String]) {
            menu.update()
            for item in menu.items where !item.isSeparatorItem && !item.isHidden && !item.title.isEmpty {
                if let sub = item.submenu {
                    if sub == NSApp.servicesMenu || sub == NSApp.windowsMenu && path.isEmpty == false { continue }
                    walk(sub, path + [item.title])
                } else if item.action != nil, item.action != #selector(NSWindow.makeKeyAndOrderFront(_:)), !item.isAlternate {
                    out.append(MenuCommand(title: item.title, path: path, shortcut: Shortcut.name(item), enabled: item.isEnabled, item: item))
                }
            }
        }
        for top in main.items {
            guard let sub = top.submenu else { continue }
            walk(sub, [top.title])
        }
        return out
    }
}

/// Key equivalents as people read them, and the ones the user gives menu commands, kept
/// where macOS keeps its App Shortcuts (`NSUserKeyEquivalents`).
enum Shortcut {
    static let defaultsKey = "NSUserKeyEquivalents"

    static let keyNames: [String: String] = [
        "\r": "↩", "\u{1b}": "⎋", "\t": "⇥", " ": "Space", "\u{8}": "⌫", "\u{7f}": "⌫",
        String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑", String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓",
        String(UnicodeScalar(NSLeftArrowFunctionKey)!): "←", String(UnicodeScalar(NSRightArrowFunctionKey)!): "→",
        String(UnicodeScalar(NSPageUpFunctionKey)!): "⇞", String(UnicodeScalar(NSPageDownFunctionKey)!): "⇟",
        String(UnicodeScalar(NSHomeFunctionKey)!): "↖", String(UnicodeScalar(NSEndFunctionKey)!): "↘",
        String(UnicodeScalar(NSDeleteFunctionKey)!): "⌦",
    ]

    /// "⇧⌘K" for a key `key` with `modifiers`.
    static func name(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        guard !key.isEmpty else { return "" }
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) || (key.count == 1 && key != key.lowercased()) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + (keyNames[key] ?? key.uppercased())
    }

    static func name(_ item: NSMenuItem) -> String {
        name(key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
    }

    /// The user's own key equivalents by menu title, in the format of `NSUserKeyEquivalents`
    /// ("@" ⌘, "$" ⇧, "~" ⌥, "^" ⌃, then the key).
    static var custom: [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    /// The `NSUserKeyEquivalents` form of a key with modifiers.
    static func equivalent(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "^" }
        if modifiers.contains(.option) { s += "~" }
        if modifiers.contains(.shift) { s += "$" }
        if modifiers.contains(.command) { s += "@" }
        return s + key.lowercased()
    }

    /// The key and modifiers of an `NSUserKeyEquivalents` value.
    static func parse(_ equivalent: String) -> (key: String, modifiers: NSEvent.ModifierFlags) {
        var modifiers: NSEvent.ModifierFlags = []
        var rest = Substring(equivalent)
        while let c = rest.first, rest.count > 1, let m = ["^": NSEvent.ModifierFlags.control, "~": .option, "$": .shift, "@": .command][c] {
            modifiers.insert(m)
            rest = rest.dropFirst()
        }
        return (String(rest), modifiers)
    }

    /// Gives the menu command `item` the key `key` with `modifiers`, or its own back for nil,
    /// now and whenever the menus are made again.
    static func assign(_ item: NSMenuItem, key: String?, modifiers: NSEvent.ModifierFlags = []) {
        var all = custom
        let title = item.title
        if let key {
            all[title] = equivalent(key: key, modifiers: modifiers)
        } else {
            all[title] = nil
        }
        UserDefaults.standard.set(all, forKey: defaultsKey)
        apply()
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        apply()
    }

    /// The key equivalents that SwiftUI gave the menu items before the user's replaced them.
    @MainActor private static var originals: [ObjectIdentifier: (String, NSEvent.ModifierFlags)] = [:]

    /// Puts the user's key equivalents on the items of the main menu: those the user chose,
    /// and their own back on the others.
    @MainActor static func apply() {
        guard let main = NSApp.mainMenu else { return }
        let all = custom
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if let sub = item.submenu {
                    walk(sub)
                    continue
                }
                let id = ObjectIdentifier(item)
                if let e = all[item.title] {
                    if originals[id] == nil { originals[id] = (item.keyEquivalent, item.keyEquivalentModifierMask) }
                    let (key, modifiers) = parse(e)
                    if item.keyEquivalent != key || item.keyEquivalentModifierMask != modifiers {
                        item.keyEquivalent = key
                        item.keyEquivalentModifierMask = modifiers
                    }
                } else if let (key, modifiers) = originals.removeValue(forKey: id) {
                    item.keyEquivalent = key
                    item.keyEquivalentModifierMask = modifiers
                }
            }
        }
        walk(main)
    }

    @MainActor private static var pending = false

    /// Keeps the user's key equivalents on the menus that SwiftUI makes again and again.
    @MainActor static func follow() {
        for name in [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    guard !pending, !custom.isEmpty || !originals.isEmpty else { return }
                    pending = true
                    DispatchQueue.main.async {
                        pending = false
                        apply()
                    }
                }
            }
        }
        apply()
    }
}
