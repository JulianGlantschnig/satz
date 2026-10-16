import SatzCore
import SwiftUI
import UniformTypeIdentifiers

/// The page overview in place of the canvas: masters in a column, the spreads beside
/// them. A click picks a page or master, Command and Shift add to the pick, a double
/// click or Return opens it; picked pages drag to a new place, delete and have a menu.
struct Overview: View {
    @Bindable var editor: Editor
    @State private var height: CGFloat = 180
    @State private var renaming: String?
    @FocusState private var focused: Bool

    private var pages: [Page] { editor.snapshot.pages }
    private var ids: [String] { pages.map(\.id) }

    var body: some View {
        let snapshot = editor.snapshot
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Masters").font(.headline)
                    ForEach(snapshot.masters) { m in master(m) }
                    Button { editor.addMaster(like: editor.overviewSelection.last ?? editor.pageID) } label: {
                        Label("New Master", systemImage: "plus")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 200)
            .background(.background.secondary)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Pages").font(.headline)
                        Spacer()
                        Slider(value: $height, in: 80...400) { Text("Size") }
                            .frame(width: 140)
                            .controlSize(.small)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: spreadWidth + 24), spacing: 20, alignment: .bottom)], alignment: .leading, spacing: 20) {
                        ForEach(rows, id: \.self) { spread in row(spread) }
                        Button { addPage() } label: {
                            Image(systemName: "plus").font(.title)
                                .frame(width: height * 0.7, height: height)
                                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary))
                        }
                        .buttonStyle(.plain)
                        .help("Add page")
                    }
                }
                .padding(16)
            }
            .contentShape(Rectangle())
            .onTapGesture { editor.overviewSelection = [] }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onDeleteCommand { deleteSelection() }
        .onKeyPress(.return) {
            if let id = editor.overviewSelection.last { open(id) }
            return .handled
        }
        .onKeyPress(.escape) {
            editor.showsOverview = false
            return .handled
        }
        .accessibilityIdentifier("overview")
    }

    /// The spreads, or each page alone without facing pages.
    private var rows: [[String]] { editor.snapshot.facingPages ? editor.snapshot.spreads : ids.map { [$0] } }

    private var spreadWidth: CGFloat {
        let widest = pages.map { $0.width / $0.height }.max() ?? 0.7
        return height * widest * (editor.snapshot.facingPages ? 2 : 1)
    }

    private func row(_ spread: [String]) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                if editor.snapshot.facingPages, spread.count == 1, spread.first == ids.first, let p = pages.first {
                    Color.clear.frame(width: height * p.width / p.height, height: 1)
                }
                ForEach(spread, id: \.self) { id in
                    if let p = pages.first(where: { $0.id == id }) { page(p) }
                }
            }
            HStack(spacing: 8) {
                ForEach(spread, id: \.self) { id in
                    let i = (ids.firstIndex(of: id) ?? 0) + 1
                    let m = editor.snapshot.masters.first { $0.id == pages.first { $0.id == id }?.master }
                    Text(verbatim: m.map { "\(i) · \(editor.prefix($0.name))" } ?? "\(i)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(spread.contains(editor.pageID ?? "") ? .primary : .secondary)
                }
            }
        }
    }

    private func page(_ p: Page) -> some View {
        let picked = editor.overviewSelection.contains(p.id)
        let n = (ids.firstIndex(of: p.id) ?? 0) + 1
        return Thumb(thumbnails: editor.thumbnails, lists: [(p.id, 0)], sheets: [Sheet(p, x: 0)], height: height)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor, lineWidth: picked ? 3 : 0))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { open(p.id) }
            .onTapGesture { click(p.id, in: ids) }
            .contextMenu { pageMenu(p) }
            .draggable(PagesDrag(ids: picked ? editor.overviewSelection.filter { ids.contains($0) } : [p.id])) {
                Thumb(thumbnails: editor.thumbnails, lists: [(p.id, 0)], sheets: [Sheet(p, x: 0)], height: 80)
            }
            .dropDestination(for: PagesDrag.self) { items, at in
                guard let moving = items.first?.ids, !moving.contains(p.id) else { return false }
                let others = ids.filter { !moving.contains($0) }
                let before = at.x < height * p.width / p.height / 2
                editor.movePages(moving, to: (others.firstIndex(of: p.id) ?? 0) + (before ? 0 : 1))
                return true
            }
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Page \(n)"))
            .accessibilityIdentifier("overview-page-\(n)")
            .accessibilityAddTraits(picked ? .isSelected : [])
    }

    @ViewBuilder private func pageMenu(_ p: Page) -> some View {
        let picked = editor.overviewSelection.contains(p.id) ? editor.overviewSelection.filter { ids.contains($0) } : [p.id]
        Button("Insert Page") {
            if let id = editor.apply(.addPage(after: p.id)).first { editor.overviewSelection = [id] }
        }
        Button("Duplicate Page") {
            if let id = editor.apply(.duplicatePage(p.id)).first { editor.overviewSelection = [id] }
        }
        Button("Create Master from Page") { editor.addMaster(like: p.id, layers: true) }
        Divider()
        Menu("Master") {
            Button { editor.useMaster(nil, on: picked) } label: {
                if p.master == nil { Label("No Master", systemImage: "checkmark") } else { Text("No Master") }
            }
            ForEach(editor.snapshot.masters) { m in
                Button { editor.useMaster(m.id, on: picked) } label: {
                    if p.master == m.id { Label(m.name, systemImage: "checkmark") } else { Text(m.name) }
                }
            }
        }
        Divider()
        Button("Delete Page", role: .destructive) { editor.deletePages(picked) }
            .disabled(picked.count >= ids.count)
    }

    private func master(_ m: Page) -> some View {
        let picked = editor.overviewSelection.contains(m.id)
        let facing = editor.snapshot.facingPages
        let sheets = facing ? [Sheet(m, x: -m.width), Sheet(m, x: 0)] : [Sheet(m, x: 0)]
        let masters = editor.snapshot.masters.map(\.id)
        return VStack(alignment: .leading, spacing: 4) {
            Thumb(thumbnails: editor.thumbnails, lists: [(m.id, m.x)], sheets: sheets, height: max(40, 160 * m.height / (m.width * (facing ? 2 : 1))))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor, lineWidth: picked ? 3 : 0))
                .onTapGesture(count: 2) { open(m.id) }
                .onTapGesture { click(m.id, in: masters) }
            if renaming == m.id {
                RenameField(name: m.name) { editor.renameMaster(m.id, $0); renaming = nil }
            } else {
                HStack(spacing: 4) {
                    Text(editor.prefix(m.name)).bold()
                    Text("·")
                    Text(m.name).lineLimit(1)
                }
                .font(.caption)
                .onTapGesture(count: 2) { renaming = m.id }
            }
        }
        .contextMenu {
            Button("Rename Master") { renaming = m.id }
            Button("Duplicate Master") { editor.addMaster(like: m.id, layers: true) }
            Button("Delete Master", role: .destructive) { editor.deleteMasters([m.id]) }
        }
        .accessibilityIdentifier("overview-master-\(m.name)")
    }

    /// A click picks `id`; Command adds or drops it, Shift spans to it, among `all`.
    private func click(_ id: String, in all: [String]) {
        focused = true
        let flags = NSEvent.modifierFlags
        let mine = editor.overviewSelection.filter { all.contains($0) }
        if flags.contains(.shift), let range = Select.span(all, selection: mine, id: id) {
            editor.overviewSelection = range
        } else if flags.contains(.command) {
            editor.overviewSelection = mine.contains(id) ? mine.filter { $0 != id } : mine + [id]
        } else {
            editor.overviewSelection = [id]
        }
    }

    private func open(_ id: String) {
        editor.showPage(id)
        editor.showsOverview = false
    }

    private func addPage() {
        if let id = editor.apply(.addPage(after: ids.last)).first { editor.overviewSelection = [id] }
    }

    private func deleteSelection() {
        let pages = editor.overviewSelection.filter { ids.contains($0) }
        let masters = editor.overviewSelection.filter { id in editor.snapshot.masters.contains { $0.id == id } }
        if !pages.isEmpty { editor.deletePages(pages) }
        if !masters.isEmpty { editor.deleteMasters(masters) }
    }
}

/// Pages dragged in the overview, by id.
nonisolated struct PagesDrag: Codable, Transferable {
    var ids: [String]
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .satzPages)
    }
}

extension UTType {
    nonisolated static let satzPages = UTType(exportedAs: "com.julianglantschnig.satz.pages")
}

/// A field that commits a new name on Return or when it loses focus.
private struct RenameField: View {
    let name: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear {
                text = name
                focused = true
            }
            .onSubmit { commit(text) }
            .onChange(of: focused) { _, now in if !now { commit(text) } }
    }
}
