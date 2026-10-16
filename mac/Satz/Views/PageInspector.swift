import SatzCore
import SwiftUI
import UniformTypeIdentifiers

/// The document's pages, spreads, raster resolution, colour mode and CMYK profile.
struct DocumentSection: View {
    let editor: Editor

    var body: some View {
        let s = editor.snapshot
        Section("Document") {
            HStack {
                NumberField(label: "Pages", value: Double(s.pages.count), unit: .plain, integer: true, range: 1...9999) { setCount(Int($0)) }
                NumberField(label: "Raster", help: "Raster resolution for transparency in print PDFs", value: s.rasterPpi, unit: .plain, integer: true, range: 72...1200) {
                    editor.apply(.setDocument(["rasterPpi": .number($0)]))
                }
            }
            Picker("Spreads", selection: Binding(get: { s.facingPages }, set: { editor.apply(.setDocument(["facingPages": .bool($0)])) })) {
                Text("Single Pages").tag(false)
                Text("Facing Pages").tag(true)
            }
            Picker("Colour mode", selection: Binding(get: { s.colorMode }, set: { editor.apply(.setDocument(["colorMode": .string($0.rawValue)])) })) {
                Text("RGB").tag(ColorMode.rgb)
                Text("CMYK").tag(ColorMode.cmyk)
            }
            if s.colorMode == .cmyk {
                Picker("Profile", selection: Binding(get: { s.profile == nil ? "fogra" : "own" }, set: { v in
                    if v == "upload" { uploadProfile() } else if v == "fogra" { editor.setProfile(nil) }
                })) {
                    Text("FOGRA51").tag("fogra")
                    if let p = s.profile { Text(p.isEmpty ? String(localized: "Uploaded") : p).tag("own") }
                    Divider()
                    Text("Upload ICC…").tag("upload")
                }
            } else {
                LabeledContent("Profile", value: "sRGB")
            }
        }
    }

    /// Adds pages at the end or deletes them from it until there are `n`.
    private func setCount(_ n: Int) {
        let pages = editor.snapshot.pages
        editor.batch {
            var last = pages.last?.id
            for _ in pages.count..<max(n, pages.count) { last = editor.apply(.addPage(after: last)).first ?? last }
            for p in pages.dropFirst(max(1, n)).reversed() { editor.apply(.deletePage(p.id)) }
        }
    }

    private func uploadProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "icc") ?? .data, UTType(filenameExtension: "icm") ?? .data]
        panel.message = String(localized: "Choose a CMYK ICC profile")
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        editor.setProfile(data)
    }
}

/// The size, format, master, modes and section of the page or master on screen, or of
/// the pages picked in the overview.
struct PageSection: View {
    let editor: Editor

    /// The pages or master the section sets.
    private var sheets: [Page] {
        let s = editor.snapshot
        if editor.showsOverview {
            let picked = s.pages.filter { editor.overviewSelection.contains($0.id) }
            if !picked.isEmpty { return picked }
        }
        return editor.page.map { [$0] } ?? []
    }

    private func each(_ props: (Page) -> Command?) {
        editor.batch {
            for p in sheets { if let c = props(p) { editor.apply(c) } }
        }
    }

    var body: some View {
        let sheets = sheets
        let s = editor.snapshot
        let isPage = sheets.allSatisfy { p in s.pages.contains { $0.id == p.id } }
        if let first = sheets.first {
            let numbers = sheets.compactMap { p in s.pages.firstIndex { $0.id == p.id }.map { $0 + 1 } }
            Section(isPage ? (numbers.count > 1 ? String(localized: "Pages \(numbers.map(String.init).joined(separator: ", "))") : String(localized: "Page \(numbers.first ?? 1)")) : String(localized: "Master")) {
                let w = same(sheets) { $0.width }
                let h = same(sheets) { $0.height }
                HStack {
                    Picker("Format", selection: Binding(
                        get: { w.flatMap { w in h.flatMap { PageFormat.name(width: w, height: $0) } } ?? "" },
                        set: { name in
                            each { p in
                                guard let size = PageFormat.size(name, landscape: p.width > p.height) else { return nil }
                                return .setPage(p.id, width: size.width, height: size.height, scale: true)
                            }
                        })
                    ) {
                        ForEach(PageFormat.all, id: \.name) { Text($0.name).tag($0.name) }
                        Text("Custom").tag("")
                    }
                    Picker("Orientation", selection: Binding(
                        get: { w.flatMap { w in h.map { w > $0 } } ?? false },
                        set: { wide in each { p in (p.width > p.height) == wide ? nil : .setPage(p.id, width: p.height, height: p.width) } })
                    ) {
                        Label("Portrait", systemImage: "rectangle.portrait").labelStyle(.iconOnly).tag(false).help("Portrait")
                        Label("Landscape", systemImage: "rectangle").labelStyle(.iconOnly).tag(true).help("Landscape")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        NumberField(label: "W", value: w, range: 1 ... .infinity) { v in each { .setPage($0.id, width: v) } }
                        NumberField(label: "H", value: h, range: 1 ... .infinity) { v in each { .setPage($0.id, height: v) } }
                    }
                    GridRow {
                        NumberField(label: "Bleed", value: same(sheets) { $0.bleed }, range: 0 ... .infinity) { v in each { .setPage($0.id, bleed: v) } }
                    }
                }
                if isPage {
                    Picker("Master", selection: Binding(
                        get: { same(sheets) { $0.master ?? "" } ?? "" },
                        set: { m in editor.useMaster(m.isEmpty ? nil : m, on: sheets.map(\.id)) })
                    ) {
                        Text("None").tag("")
                        ForEach(s.masters) { Text($0.name).tag($0.id) }
                    }
                }
                ModePickers(editor: editor, id: first.id, own: first.modes, inherited: [:])
                if isPage, sheets.count == 1 {
                    let n = numbers.first ?? 1
                    Toggle("Start section", isOn: Binding(
                        get: { first.section != nil },
                        set: { on in
                            if let cmd = try? Command.setSection(first.id, on ? Section(start: n, style: .arabic, prefix: "") : nil) { editor.apply(cmd) }
                        }))
                    if let section = first.section {
                        HStack {
                            NumberField(label: "Start", help: "Section starts at", value: Double(section.start), unit: .plain, integer: true, range: 1...99999) { v in
                                setSection(first, section) { $0.start = Int(v) }
                            }
                            Picker("Numbering", selection: Binding(get: { section.style }, set: { st in setSection(first, section) { $0.style = st } })) {
                                Text(verbatim: "1, 2, 3").tag(SatzCore.Section.Style.arabic)
                                Text(verbatim: "I, II, III").tag(SatzCore.Section.Style.upperRoman)
                                Text(verbatim: "i, ii, iii").tag(SatzCore.Section.Style.lowerRoman)
                            }
                            .labelsHidden()
                        }
                        TextField("Prefix", text: Binding(get: { section.prefix }, set: { p in setSection(first, section) { $0.prefix = p } }))
                    }
                }
                HStack {
                    if isPage, sheets.contains(where: { !$0.detached.isEmpty }) {
                        Button("Reset Overrides") { editor.apply(.resetToMaster(sheets.map(\.id))) }
                    }
                    if isPage, sheets.count == 1, s.pages.contains(where: { $0.width != first.width || $0.height != first.height || $0.bleed != first.bleed }) {
                        Button("Apply Size to All Pages") {
                            editor.batch {
                                for p in s.pages { editor.apply(.setPage(p.id, width: first.width, height: first.height, bleed: first.bleed)) }
                            }
                        }
                    }
                }
                .controlSize(.small)
            }
            GridSection(editor: editor, sheets: sheets, all: isPage && sheets.count == 1 ? s.pages : [])
        }
    }

    private func setSection(_ page: Page, _ section: SatzCore.Section, _ change: (inout SatzCore.Section) -> Void) {
        var s = section
        change(&s)
        if let cmd = try? Command.setSection(page.id, s) { editor.apply(cmd) }
    }
}

/// The layout grids of `sheets`, with presets, and a button that gives them to `all` when they differ.
struct GridSection: View {
    let editor: Editor
    let sheets: [Page]
    let all: [Page]

    static let presets: [(LocalizedStringKey, [(SatzCore.Grid.Kind, Int)])] = [
        ("1 column", [(.columns, 1)]), ("2 columns", [(.columns, 2)]), ("3 columns", [(.columns, 3)]), ("4 columns", [(.columns, 4)]),
        ("12 columns", [(.columns, 12)]), ("3 × 3 modules", [(.columns, 3), (.rows, 3)]), ("6 × 6 modules", [(.columns, 6), (.rows, 6)]),
        ("5 mm grid", [(.grid, 1)]),
    ]

    private func setGrids(_ grids: [SatzCore.Grid], on pages: [Page]? = nil) {
        editor.batch {
            for p in pages ?? sheets { if let cmd = try? Command.setGrids(p.id, grids) { editor.apply(cmd) } }
        }
    }

    var body: some View {
        let grids = same(sheets) { $0.grids }
        Section {
            if let grids {
                ForEach(grids.indices, id: \.self) { i in
                    let g = grids[i]
                    let set = { (change: (inout SatzCore.Grid) -> Void) in
                        var list = grids
                        change(&list[i])
                        setGrids(list)
                    }
                    HStack {
                        Picker("Grid type", selection: Binding(get: { g.kind }, set: { k in set { $0.kind = k } })) {
                            Text("Columns").tag(SatzCore.Grid.Kind.columns)
                            Text("Rows").tag(SatzCore.Grid.Kind.rows)
                            Text("Grid").tag(SatzCore.Grid.Kind.grid)
                        }
                        .labelsHidden()
                        Spacer()
                        Button {
                            var list = grids
                            list.remove(at: i)
                            setGrids(list)
                        } label: { Image(systemName: "minus") }
                            .buttonStyle(.borderless)
                            .help("Remove grid")
                    }
                    if g.kind == .grid {
                        NumberField(label: "Size", help: "Cell size", value: g.size, range: 0.1 ... .infinity) { v in set { $0.size = v } }
                    } else {
                        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                            GridRow {
                                NumberField(label: g.kind == .columns ? "Columns" : "Rows", value: Double(g.count), unit: .plain, integer: true, range: 1...100) { v in set { $0.count = Int(v) } }
                                NumberField(label: "Gutter", value: g.gutter, range: 0 ... .infinity) { v in set { $0.gutter = v } }
                            }
                            GridRow {
                                NumberField(label: "Margin", value: g.margin, range: 0 ... .infinity) { v in set { $0.margin = v } }
                            }
                        }
                    }
                }
                if !all.isEmpty, all.contains(where: { $0.grids != sheets.first?.grids }) {
                    Button("Apply Grids to All Pages") { setGrids(grids, on: all) }
                        .controlSize(.small)
                }
            } else {
                Text("Mixed · + replaces").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Layout Grids")
                Spacer()
                Menu {
                    ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, preset in
                        Button(preset.0) {
                            let made = preset.1.map { kind, count in
                                SatzCore.Grid(kind: kind, count: count, gutter: Units.mm(count > 6 ? 4 : 5), margin: Units.mm(15), size: Units.mm(5))
                            }
                            setGrids((grids ?? []) + made)
                        }
                    }
                } label: { Image(systemName: "plus") }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add layout grid")
            }
        }
    }
}
