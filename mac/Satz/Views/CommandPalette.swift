import AppKit
import SatzCore
import SwiftUI

/// What the command palette and the shortcuts list offer besides the menus: the tools and
/// the keys and gestures of the canvas; see `web/src/Help.tsx`.
struct CanvasKey: Identifiable {
    var id: String { group + title }
    var group: String
    var title: String
    var keys: String
    var run: (@MainActor (Editor) -> Void)?

    static var all: [CanvasKey] {
        let tools = Editor.Tool.allCases.map { tool in
            CanvasKey(group: String(localized: "Tools"), title: String(localized: tool.title), keys: tool.key.uppercased()) { $0.tool = tool }
        }
        let canvas = String(localized: "Canvas")
        let path = String(localized: "Path")
        let text = String(localized: "Text")
        let fields = String(localized: "Fields")
        let keys = Dictionary(uniqueKeysWithValues: CanvasView.alignKeys.map { ($1, $0) })
        let aligns = Editor.Align.allCases.map { a in
            CanvasKey(group: String(localized: "Align"), title: String(localized: a.title), keys: keys[a].map { "⌥" + $0.uppercased() } ?? "") { $0.align(a) }
        }
        return tools + aligns + [
            CanvasKey(group: canvas, title: String(localized: "Select a layer inside a group"), keys: "⌘ " + String(localized: "click")),
            CanvasKey(group: canvas, title: String(localized: "Override a master layer on this page"), keys: "⇧⌘ " + String(localized: "click")),
            CanvasKey(group: canvas, title: String(localized: "Edit a text, the points of a shape or crop an image"), keys: String(localized: "Double-click")),
            CanvasKey(group: canvas, title: String(localized: "Resize from the centre"), keys: "⌥ " + String(localized: "drag")),
            CanvasKey(group: canvas, title: String(localized: "Copy while moving"), keys: "⌥ " + String(localized: "drag")),
            CanvasKey(group: canvas, title: String(localized: "Move without snapping"), keys: "⌘ " + String(localized: "drag")),
            CanvasKey(group: canvas, title: String(localized: "Move along one axis"), keys: "⇧ " + String(localized: "drag")),
            CanvasKey(group: canvas, title: String(localized: "Pan the view"), keys: String(localized: "Space drag")),
            CanvasKey(group: canvas, title: String(localized: "Nudge by 0.1 mm, with Shift by 1 mm"), keys: "← → ↑ ↓"),
            CanvasKey(group: canvas, title: String(localized: "Select the next or previous layer"), keys: "⇥ ⇧⇥"),
            CanvasKey(group: canvas, title: String(localized: "Select the children or the parent"), keys: "↩ ⇧↩"),
            CanvasKey(group: canvas, title: String(localized: "Flip horizontally or vertically"), keys: "⇧H ⇧V") { $0.flip(vertical: false) },
            CanvasKey(group: canvas, title: String(localized: "Add Auto Layout"), keys: "⇧A") { $0.addAutoLayout() },
            CanvasKey(group: canvas, title: String(localized: "Remove Auto Layout"), keys: "⌥⇧A") { $0.removeAutoLayout() },
            CanvasKey(group: canvas, title: String(localized: "Show or hide layout grids and guides"), keys: "⇧G") { $0.showsGrids.toggle() },
            CanvasKey(group: canvas, title: String(localized: "Page Overview"), keys: ".") { $0.toggleOverview() },
            CanvasKey(group: canvas, title: String(localized: "Zoom to Fit"), keys: "⇧1") { $0.canvas?.fit() },
            CanvasKey(group: canvas, title: String(localized: "Zoom to Selection"), keys: "⇧2") { $0.canvas?.zoomToSelection() },
            CanvasKey(group: canvas, title: String(localized: "Add a guide; drag it back or press Delete to remove it"), keys: String(localized: "Drag from a ruler")),
            CanvasKey(group: path, title: String(localized: "Move Points"), keys: "V"),
            CanvasKey(group: path, title: String(localized: "Add Points"), keys: "P"),
            CanvasKey(group: path, title: String(localized: "Delete Points"), keys: "-"),
            CanvasKey(group: path, title: String(localized: "Fill Areas"), keys: "B"),
            CanvasKey(group: path, title: String(localized: "Smooth or corner point"), keys: "⌘ " + String(localized: "click")),
            CanvasKey(group: path, title: String(localized: "Pick several points"), keys: "⇧ " + String(localized: "click")),
            CanvasKey(group: path, title: String(localized: "Done"), keys: "↩ ⎋"),
            CanvasKey(group: text, title: String(localized: "Edit the selected text"), keys: "↩"),
            CanvasKey(group: text, title: String(localized: "Stop editing the text"), keys: "⎋"),
            CanvasKey(group: text, title: String(localized: "Insert placeholder text, lorem50 for 50 words"), keys: "lorem ⇥"),
            CanvasKey(group: text, title: String(localized: "Unthread a text frame"), keys: String(localized: "Double-click a port")),
            CanvasKey(group: fields, title: String(localized: "Change the value"), keys: String(localized: "Drag the label")),
            CanvasKey(group: fields, title: String(localized: "Step by 1, with Shift by 10, with Option by 0.1"), keys: "↑ ↓"),
            CanvasKey(group: fields, title: String(localized: "Calculate, with units"), keys: "118/2 + 1cm"),
        ]
    }
}

/// ⌘K: finds a command of the menus or the canvas by its name and runs it; see
/// `web/src/App.tsx`.
struct CommandPalette: View {
    let editor: Editor
    @State private var query = ""
    @State private var picked = 0
    @State private var menus: [MenuCommand] = []
    @FocusState private var focused: Bool

    struct Row: Identifiable {
        var id: String
        var title: String
        var place: String
        var shortcut: String
        var enabled: Bool
        var run: @MainActor () -> Void
    }

    private var rows: [Row] {
        let canvas = CanvasKey.all.compactMap { k -> Row? in
            guard let run = k.run else { return nil }
            return Row(id: k.id, title: k.title, place: k.group, shortcut: k.keys, enabled: true) { [editor] in run(editor) }
        }
        let all = menus.map { m in Row(id: m.id, title: m.title, place: m.path.joined(separator: " ▸ "), shortcut: m.shortcut, enabled: m.enabled, run: m.run) }
            + canvas + documentRows
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return all }
        return all.filter { r in
            let text = "\(r.place) \(r.title)".lowercased()
            return words.allSatisfy { text.contains($0) }
        }.sorted { a, b in
            // Titles that start with the query first.
            let (x, y) = (a.title.lowercased().hasPrefix(words[0]), b.title.lowercased().hasPrefix(words[0]))
            return x && !y
        }
    }

    /// The layers, pages, swatches and text styles of the document; see `web/src/Palette.tsx`.
    private var documentRows: [Row] {
        let s = editor.snapshot
        let e = editor
        func flat(_ nodes: [Node]) -> [Node] { nodes.flatMap { [$0] + flat($0.children ?? []) } }
        let layers = s.pages.enumerated().flatMap { i, p in
            flat(p.children).map { n in
                Row(id: "layer-\(n.id)", title: n.name, place: String(localized: "Layers · Page \(i + 1)"), shortcut: "", enabled: true) {
                    e.showsOverview = false
                    e.showPage(p.id)
                    e.select([n.id])
                }
            }
        }
        let pages = s.pages.enumerated().map { i, p in
            Row(id: "page-\(p.id)", title: String(localized: "Page \(i + 1)"), place: String(localized: "Pages"), shortcut: "", enabled: true) {
                e.showsOverview = false
                e.showPage(p.id)
            }
        }
        let swatches = s.swatches.map { w in
            Row(id: "swatch-\(w.id)", title: String(localized: "Fill with \(w.name)"), place: String(localized: "Swatches"), shortcut: "", enabled: true) {
                guard !e.selection.isEmpty, let fill = try? JSON(encoding: [Fill.solid(.swatch(w.id, tint: 1, alpha: 1))]) else {
                    e.fail(String(localized: "Select a layer first"))
                    return
                }
                e.batch {
                    for n in e.selected { e.apply(.set(id: n.id, ["fills": fill])) }
                }
            }
        }
        let styles = s.textStyles.map { t in
            Row(id: "style-\(t.id)", title: String(localized: "Style \(t.name)"), place: String(localized: "Text styles"), shortcut: "", enabled: true) {
                let texts = e.selected.filter { $0.kind == .text }
                guard !texts.isEmpty else {
                    e.fail(String(localized: "Select a text first"))
                    return
                }
                e.batch {
                    for n in texts { e.apply(.format(id: n.id, range: nil, ["textStyle": .string(t.id)])) }
                }
            }
        }
        return layers + pages + swatches + styles
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search commands, layers, pages, swatches, styles", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { run(rows) }
                    .onKeyPress(.upArrow) {
                        picked = max(picked - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        picked = min(picked + 1, rows.count - 1)
                        return .handled
                    }
                    .onExitCommand { close() }
                    .accessibilityIdentifier("palette-search")
            }
            .padding(12)
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                            Button {
                                picked = i
                                run(rows)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.title)
                                        Text(r.place).font(.caption).foregroundStyle(i == picked ? .white.opacity(0.8) : .secondary)
                                    }
                                    Spacer()
                                    Text(r.shortcut).font(.callout.monospaced()).foregroundStyle(i == picked ? .white.opacity(0.9) : .secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .foregroundStyle(i == picked ? SwiftUI.Color.white : r.enabled ? .primary : .secondary)
                                .background(i == picked ? SwiftUI.Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if rows.isEmpty {
                            Text("No command matches.").foregroundStyle(.secondary).padding()
                        }
                    }
                    .padding(6)
                }
                .onChange(of: picked) { if rows.indices.contains(picked) { scroll.scrollTo(rows[picked].id) } }
            }
            .frame(height: min(CGFloat(max(rows.count, 1)) * 40 + 12, 360))
        }
        .frame(width: 520)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(radius: 20, y: 8)
        .onAppear {
            menus = MenuCommand.all()
            focused = true
        }
        .onChange(of: query) { picked = 0 }
    }

    private func run(_ rows: [Row]) {
        guard rows.indices.contains(picked), rows[picked].enabled else { return }
        let r = rows[picked]
        close()
        // After the palette has gone, so that the command goes to the canvas.
        DispatchQueue.main.async { r.run() }
    }

    private func close() {
        editor.showsPalette = false
        if let canvas = editor.canvas { canvas.window?.makeFirstResponder(canvas) }
    }
}
