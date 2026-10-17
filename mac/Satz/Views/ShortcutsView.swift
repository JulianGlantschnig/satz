import AppKit
import SwiftUI

/// Every shortcut by where it works; a click on the keys of a menu command records new
/// ones; see `web/src/Help.tsx`.
struct ShortcutsView: View {
    let editor: Editor
    @State private var query = ""
    @State private var menus: [MenuCommand] = []
    @State private var recording: String?
    @State private var monitor: Any?
    @State private var custom = Shortcut.custom

    private struct Group: Identifiable {
        var id: String
        var rows: [Row]
    }

    private struct Row: Identifiable {
        var id: String
        var title: String
        var keys: String
        var command: MenuCommand?
    }

    private var groups: [Group] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        var order: [String] = []
        var by: [String: [Row]] = [:]
        func add(_ group: String, _ row: Row) {
            if by[group] == nil { order.append(group) }
            by[group, default: []].append(row)
        }
        for k in CanvasKey.all { add(k.group, Row(id: k.id, title: k.title, keys: k.keys)) }
        for m in menus {
            add(m.path.first ?? "", Row(id: m.id, title: m.path.count > 1 ? m.path.dropFirst().joined(separator: " ▸ ") + " ▸ " + m.title : m.title, keys: m.shortcut, command: m))
        }
        return order.compactMap { g in
            let rows = by[g]!.filter { q.isEmpty || "\(g) \($0.title) \($0.keys)".lowercased().contains(q) }
            return rows.isEmpty ? nil : Group(id: g, rows: rows)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts").font(.title2.weight(.semibold))
                Spacer()
                Button("Reset Shortcuts") {
                    Shortcut.reset()
                    reload()
                }
                .disabled(custom.isEmpty)
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .accessibilityIdentifier("shortcuts-search")
                Button("Done") { editor.showsShortcuts = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), alignment: .top)], alignment: .leading, spacing: 20) {
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g.id).font(.headline).padding(.bottom, 2)
                            ForEach(g.rows) { r in row(r) }
                        }
                    }
                }
                .padding(16)
                if groups.isEmpty {
                    Text("No shortcut matches.").foregroundStyle(.secondary).padding()
                }
            }
            Text("Click the keys of a menu command and press new ones with ⌘ or ⌃; ⌫ gives it its own back, ⎋ cancels.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .frame(width: 760, height: 560)
        .onAppear { reload() }
        .onDisappear { stopRecording() }
    }

    private func row(_ r: Row) -> some View {
        HStack {
            Text(r.title).lineLimit(1)
            Spacer()
            if let c = r.command, let item = c.item {
                if custom[item.title] != nil {
                    Button {
                        Shortcut.assign(item, key: nil)
                        reload()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to the default")
                }
                Button {
                    record(c)
                } label: {
                    Text(recording == c.id ? String(localized: "Press keys…") : c.shortcut.isEmpty ? "—" : c.shortcut)
                        .font(.callout.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(recording == c.id ? SwiftUI.Color.accentColor.opacity(0.3) : SwiftUI.Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Click and press new keys")
                .accessibilityIdentifier("keys-\(c.id)")
            } else {
                Text(r.keys).font(.callout.monospaced()).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private func reload() {
        menus = MenuCommand.all()
        custom = Shortcut.custom
    }

    /// Takes the next key pressed with ⌘ or ⌃ as the shortcut of `c`.
    private func record(_ c: MenuCommand) {
        stopRecording()
        recording = c.id
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if event.keyCode == 53 {
                stopRecording()
            } else if event.keyCode == 51 && flags.isEmpty, let item = c.item {
                Shortcut.assign(item, key: nil)
                stopRecording()
                reload()
            } else if !key.isEmpty, flags.contains(.command) || flags.contains(.control), let item = c.item {
                Shortcut.assign(item, key: key, modifiers: flags)
                stopRecording()
                reload()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}
