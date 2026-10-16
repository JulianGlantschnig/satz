import SatzCore
import SwiftUI
import UniformTypeIdentifiers

/// The left panel: the pages and masters, and the layers of the spread on screen, topmost first.
struct Sidebar: View {
    @Bindable var editor: Editor
    @State private var renaming: String?

    enum Item: Hashable {
        case page(String)
        case layer(String)
    }

    /// A layer in the list, its children topmost first.
    struct Layer: Identifiable {
        var node: Node
        var children: [Layer]?
        var id: String { node.id }
    }

    private var layers: [Layer] {
        /// Auto layout frames list their children in flow order, others topmost first.
        func wrap(_ nodes: [Node], flow: Bool = false) -> [Layer] {
            (flow ? nodes : nodes.reversed()).map { n in
                Layer(node: n, children: n.children.map { wrap($0, flow: n.kind == .frame && n.direction != .none) })
            }
        }
        let pages = editor.master.map { [$0] } ?? editor.spread
        return pages.reversed().flatMap { wrap($0.children) }
    }

    private var selection: Binding<Set<Item>> {
        Binding {
            var s = Set(editor.selection.map(Item.layer))
            if editor.selection.isEmpty, let id = editor.pageID { s.insert(.page(id)) }
            return s
        } set: { new in
            let ids = new.compactMap { if case .layer(let id) = $0 { id } else { nil } }
            let page = new.compactMap { if case .page(let id) = $0 { id } else { nil } }.first
            if ids.isEmpty, let page {
                editor.showPage(page)
                editor.select([])
            } else {
                // Keep the order the layers were chosen in.
                let kept = editor.selection.filter { ids.contains($0) }
                editor.select(kept + ids.filter { !kept.contains($0) })
            }
        }
    }

    var body: some View {
        List(selection: selection) {
            Section("Pages") {
                ForEach(Array(editor.snapshot.pages.enumerated()), id: \.element.id) { i, page in
                    Label(String(localized: "Page \(i + 1)"), systemImage: "doc")
                        .tag(Item.page(page.id))
                        .accessibilityIdentifier("page-\(i + 1)")
                }
            }
            if !editor.snapshot.masters.isEmpty {
                Section("Masters") {
                    ForEach(editor.snapshot.masters) { master in
                        Label(master.name, systemImage: "doc.on.doc")
                            .tag(Item.page(master.id))
                            .accessibilityIdentifier("master-\(master.name)")
                    }
                }
            }
            Section("Layers") {
                OutlineGroup(layers, children: \.children) { layer in
                    LayerRow(editor: editor, node: layer.node, renaming: $renaming)
                        .tag(Item.layer(layer.id))
                }
            }
        }
        .contextMenu(forSelectionType: Item.self) { items in
            let ids = items.compactMap { if case .layer(let id) = $0 { id } else { nil } }
            if !ids.isEmpty {
                Button("Rename") { renaming = ids.first }
                Button("Show or Hide") {
                    editor.select(ids)
                    editor.toggle("hidden")
                }
                Button("Lock or Unlock") {
                    editor.select(ids)
                    editor.toggle("locked")
                }
                Divider()
                Button("Group") {
                    editor.select(ids)
                    editor.group()
                }
                Button("Delete", role: .destructive) {
                    editor.select(ids)
                    editor.delete()
                }
            }
        }
        .onDeleteCommand { editor.delete() }
    }
}

/// A layer in the list: its kind, name, and buttons to hide and lock it.
struct LayerRow: View {
    let editor: Editor
    let node: Node
    @Binding var renaming: String?
    @State private var name = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var symbol: String {
        switch node.kind {
        case .text: "textformat"
        case .group: "square.on.square.dashed"
        case .frame: node.direction == .none ? "number" : node.direction == .horizontal ? "arrow.left.and.right" : "arrow.up.and.down"
        case .shape:
            if node.fills.contains(where: { $0.type == .image }) { "photo" } else {
                switch node.shape {
                case .ellipse: "circle"
                case .polygon: "triangle"
                case .star: "star"
                case .path: Editor.ends(node) != nil ? "line.diagonal" : "scribble"
                default: "rectangle"
                }
            }
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.mask ? "theatermask.and.paintbrush" : symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            if renaming == node.id {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { renaming = nil }
                    .onAppear {
                        name = node.name
                        focused = true
                    }
                    .onChange(of: focused) { _, now in if !now { commit() } }
            } else {
                Text(node.name)
                    .lineLimit(1)
                    .foregroundStyle(node.hidden ? .secondary : .primary)
                    .onTapGesture(count: 2) { renaming = node.id }
            }
            if node.overrideOf != nil {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary).help("Overrides its master layer")
            }
            Spacer(minLength: 4)
            if hovering || node.locked {
                toggle(node.locked ? "lock.fill" : "lock.open", "locked", help: node.locked ? "Unlock" : "Lock")
            }
            if hovering || node.hidden {
                toggle(node.hidden ? "eye.slash" : "eye", "hidden", help: node.hidden ? "Show" : "Hide")
            }
        }
        .contentShape(Rectangle())
        .onHover { on in
            hovering = on
            editor.hover = on ? node.id : (editor.hover == node.id ? nil : editor.hover)
        }
        .draggable(node.id)
        .dropDestination(for: String.self) { ids, _ in drop(ids) }
        .accessibilityIdentifier("layer-\(node.name)")
    }

    private func toggle(_ symbol: String, _ prop: String, help: LocalizedStringKey) -> some View {
        Button {
            let on = prop == "hidden" ? !node.hidden : !node.locked
            editor.apply(.set(id: node.id, [prop: .bool(on)]))
        } label: {
            Image(systemName: symbol).frame(width: 16)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func commit() {
        guard renaming == node.id else { return }
        renaming = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && trimmed != node.name { editor.apply(.set(id: node.id, ["name": .string(trimmed)])) }
    }

    /// Puts the dropped layers above this one, in its parent.
    private func drop(_ ids: [String]) -> Bool {
        let ids = ids.filter { $0 != node.id && editor.nodes[$0] != nil }
        guard !ids.isEmpty, let entry = editor.nodes[node.id] else { return false }
        let siblings = entry.parent?.children ?? entry.page?.children ?? []
        guard let parent = entry.parent?.id ?? entry.page?.id, let at = siblings.firstIndex(where: { $0.id == node.id }) else { return false }
        // The index counts the other children. Children are kept bottom first, so above this
        // row is after it, unless the parent lists them in flow order.
        let flows = entry.parent.map { $0.kind == .frame && $0.direction != .none } ?? false
        let before = siblings[..<at].filter { ids.contains($0.id) }.count
        editor.apply(.move(ids, parent: parent, index: at - before + (flows ? 0 : 1)))
        editor.select(ids)
        return true
    }
}
