import SatzCore
import SwiftUI
import UniformTypeIdentifiers

/// The left panel in two tabs: the pages and masters as small pictures, or the layers of the
/// page on screen or of its spread under a heading per page, topmost first.
struct Sidebar: View {
    @Bindable var editor: Editor

    /// A layer in the list, its children topmost first.
    struct Layer: Identifiable {
        var node: Node
        var children: [Layer]?
        var id: String { node.id }
    }

    @AppStorage(LayersShown.key) private var shown = LayersShown.page

    /// The layers of `page`, topmost first; auto layout frames list their children in flow order.
    private func layers(of page: Page) -> [Layer] {
        func wrap(_ nodes: [Node], flow: Bool = false) -> [Layer] {
            (flow ? nodes : nodes.reversed()).map { n in
                Layer(node: n, children: n.children.map { wrap($0, flow: n.kind == .frame && n.direction != .none) })
            }
        }
        return wrap(page.children)
    }

    /// The pages whose layers are listed: the master on screen, the current page, or its spread.
    private var listed: [Page] {
        if let m = editor.master { return [m] }
        if shown == .spread { return editor.spread }
        return editor.page.map { [$0] } ?? []
    }

    private func number(_ p: Page) -> Int { (editor.snapshot.pages.firstIndex { $0.id == p.id } ?? 0) + 1 }

    /// "Layers · Page 2", "Layers · Pages 2–3" or the master's name; see `web/src/Layers.tsx`.
    private var heading: String {
        if let m = editor.master { return String(localized: "Layers · \(m.name)") }
        let n = listed.map(number)
        guard let first = n.first, let last = n.last else { return String(localized: "Layers") }
        return first == last ? String(localized: "Layers · Page \(first)") : String(localized: "Layers · Pages \(first)–\(last)")
    }

    /// The tab the sidebar shows.
    enum Tab: String { case pages, layers }
    @AppStorage("sidebarTab") private var tab = Tab.layers

    private var layerSelection: Binding<Set<String>> {
        Binding {
            Set(editor.selection)
        } set: { ids in
            // Keep the order the layers were chosen in.
            let kept = editor.selection.filter { ids.contains($0) }
            editor.select(kept + ids.filter { !kept.contains($0) })
        }
    }

    private var pageSelection: Binding<String?> {
        Binding { editor.pageID } set: { id in
            guard let id else { return }
            editor.showPage(id)
            editor.select([])
        }
    }

    private func rows(_ page: Page) -> some View {
        OutlineGroup(layers(of: page), children: \.children) { layer in
            LayerRow(editor: editor, node: layer.node, renaming: $editor.renaming)
                .tag(layer.id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $tab) {
                Text("Pages").tag(Tab.pages).accessibilityIdentifier("tab-pages")
                Text("Layers").tag(Tab.layers).accessibilityIdentifier("tab-layers")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .accessibilityIdentifier("sidebar-tabs")
            switch tab {
            case .pages: pagesList
            case .layers: layersList
            }
        }
    }

    /// The pages as small pictures, numbered with their master, and the masters under them.
    private var pagesList: some View {
        let s = editor.snapshot
        return List(selection: pageSelection) {
            Section {
                ForEach(Array(s.pages.enumerated()), id: \.element.id) { i, page in
                    PageRow(editor: editor, page: page, number: i + 1)
                        .tag(page.id)
                        .contextMenu {
                            Button("Insert Page") { if let id = editor.apply(.addPage(after: page.id)).first { editor.showPage(id) } }
                            Button("Duplicate Page") { if let id = editor.apply(.duplicatePage(page.id)).first { editor.showPage(id) } }
                            Divider()
                            Button("Delete Page", role: .destructive) { editor.deletePages([page.id]) }
                                .disabled(s.pages.count < 2)
                        }
                }
                .onMove { from, to in
                    guard let i = from.first else { return }
                    let moving = s.pages[i].id
                    editor.movePages([moving], to: to > i ? to - 1 : to)
                }
            }
            if !s.masters.isEmpty {
                Section("Masters") {
                    ForEach(s.masters) { master in
                        PageRow(editor: editor, page: master, number: nil)
                            .tag(master.id)
                            .accessibilityIdentifier("master-\(master.name)")
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var layersList: some View {
        List(selection: layerSelection) {
            Section {
                if listed.count > 1 {
                    ForEach(listed) { page in
                        DisclosureGroup {
                            rows(page)
                        } label: {
                            Text("Page \(number(page))").fontWeight(.medium)
                        }
                    }
                } else if let page = listed.first {
                    rows(page)
                }
            } header: {
                Text(heading).accessibilityIdentifier("layers-heading")
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 24)
        .contextMenu(forSelectionType: String.self) { ids in
            if !ids.isEmpty {
                let ids = Array(ids)
                Button("Rename") { editor.renaming = ids.first }
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

/// A page or master in the pages tab: its picture, number and master.
private struct PageRow: View {
    let editor: Editor
    let page: Page
    /// Nil for a master.
    let number: Int?

    var body: some View {
        let master = editor.snapshot.masters.first { $0.id == page.master }
        HStack(alignment: .center, spacing: 10) {
            Text(verbatim: number.map(String.init) ?? editor.prefix(page.name))
                .font(.system(size: Theme.small, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
            Thumb(thumbnails: editor.thumbnails, lists: [(page.id, 0)], sheets: [Sheet(page, x: 0)], height: number == nil ? 40 : 56)
            VStack(alignment: .leading, spacing: 2) {
                if number == nil {
                    Text(page.name).font(.system(size: Theme.small, weight: .medium)).lineLimit(1)
                } else if let master {
                    Text(master.name).font(.system(size: Theme.small)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(number.map { String(localized: "Page \($0)") } ?? page.name)
        .accessibilityIdentifier(number.map { "page-\($0)" } ?? "master-\(page.name)")
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

/// What the layers panel lists, as the settings choose.
enum LayersShown: String, CaseIterable, Identifiable {
    case page, spread

    static let key = "layers"
    var id: Self { self }

    var title: String {
        switch self {
        case .page: String(localized: "Current page")
        case .spread: String(localized: "Current spread")
        }
    }
}
