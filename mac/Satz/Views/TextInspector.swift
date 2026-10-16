import CoreText
import SatzCore
import SwiftUI

/// Text settings in the inspector; see `web/src/Text.tsx`.
extension Sizing {
    enum Resizing: String, CaseIterable, Identifiable {
        case autoWidth, autoHeight, fixedSize
        var id: String { rawValue }
    }

    /// Figma's text resize modes: auto width hugs both sides, auto height the height.
    func text(_ mode: Resizing) -> Sizing {
        let width: Size = horizontal == .hug ? .fixed : horizontal
        switch mode {
        case .autoWidth: return Sizing(horizontal: .hug, vertical: .hug)
        case .autoHeight: return Sizing(horizontal: width, vertical: .hug)
        case .fixedSize: return Sizing(horizontal: width, vertical: vertical == .fill ? .fill : .fixed)
        }
    }

    var resizing: Resizing { horizontal == .hug ? .autoWidth : vertical == .hug ? .autoHeight : .fixedSize }
}

/// The value all spans share, or nil.
func shared<T: Equatable>(_ spans: [Attrs], _ get: (Attrs) -> T) -> T? {
    guard let first = spans.first.map(get) else { return nil }
    return spans.dropFirst().allSatisfy { get($0) == first } ? first : nil
}

/// Style, font, size and alignment of the selected text layers, or of the selection
/// in the text being edited.
struct TextSection: View {
    let editor: Editor
    let nodes: [Node]

    /// The attributes of the edited range, or of all the text of the layers.
    private var spans: [Attrs] {
        if let e = editor.editing, !e.isCaret, let n = editor.nodes[e.id]?.node, let story = editor.story(of: n) {
            var at = 0
            return story.spans.compactMap { s -> Attrs? in
                defer { at += s.len }
                return at < e.range.upperBound && at + s.len > e.range.lowerBound ? s.attrs : nil
            }
        }
        var seen = Set<String>()
        return nodes.compactMap { $0.story }.filter { seen.insert($0).inserted }.flatMap { editor.snapshot.stories[$0]?.spans.map(\.attrs) ?? [] }
    }

    /// Formats the selection of the text being edited, or else all of each layer.
    func format(_ props: [String: JSON]) {
        if let e = editor.editing, !e.isCaret {
            editor.apply(.format(id: e.id, range: e.range, props))
            return
        }
        editor.batch {
            var seen = Set<String>()
            for n in nodes where seen.insert(n.story ?? n.id).inserted {
                editor.apply(.format(id: n.id, range: nil, props))
            }
        }
    }

    private func number(_ key: String) -> (Double) -> Void { { format([key: .number($0)]) } }

    var body: some View {
        let spans = spans
        Section("Text") {
            HStack {
                StyleMenu(editor: editor, spans: spans, format: format)
                CharacterMenu(editor: editor, node: nodes.first)
            }
            let font: Typeface?? = shared(spans) { $0.font }
            FontMenu(editor: editor, value: font ?? nil, mixed: font == nil && !spans.isEmpty) { face in
                format(["font": (try? JSON(encoding: face)) ?? .null])
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    if nodes.count == 1 {
                        VariableBinding(editor: editor, id: nodes[0].id, prop: "size", title: "Font size", value: shared(spans) { $0.size }) {
                            NumberField(label: "Size", help: "Font size", value: shared(spans) { $0.size }, unit: .points, range: 0.1 ... 5000, commit: number("size"))
                        }
                    } else {
                        NumberField(label: "Size", help: "Font size", value: shared(spans) { $0.size }, unit: .points, range: 0.1 ... 5000, commit: number("size"))
                    }
                    NumberField(label: "Line", help: "Line height", value: shared(spans) { $0.lineHeight }, unit: .points, range: 0 ... 5000, zero: String(localized: "Auto"), commit: number("lineHeight"))
                }
                GridRow {
                    NumberField(label: "Track", help: "Letter spacing", value: shared(spans) { $0.letterSpacing }, unit: .percent, range: -100 ... 1000, commit: number("letterSpacing"))
                    NumberField(label: "After", help: "Paragraph spacing", value: shared(spans) { $0.paragraphSpacing }, unit: .points, range: 0 ... 5000, commit: number("paragraphSpacing"))
                }
            }
            HStack {
                Picker("Align", selection: Binding(
                    get: { shared(spans) { $0.textAlign } ?? .left },
                    set: { format(["textAlign": .string($0.rawValue)]) })
                ) {
                    Label("Align left", systemImage: "text.alignleft").labelStyle(.iconOnly).tag(Attrs.TextAlign.left).help("Align left")
                    Label("Align center", systemImage: "text.aligncenter").labelStyle(.iconOnly).tag(Attrs.TextAlign.center).help("Align center")
                    Label("Align right", systemImage: "text.alignright").labelStyle(.iconOnly).tag(Attrs.TextAlign.right).help("Align right")
                    Label("Justify", systemImage: "text.justify").labelStyle(.iconOnly).tag(Attrs.TextAlign.justify).help("Justify")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TypeOptions(spans: spans, set: format)
            }
            let shading: SatzCore.Color?? = shared(spans) { $0.shading }
            ColorCheck(
                editor: editor, label: "Shading", color: shading,
                modes: nodes.first?.activeModes ?? [:]
            ) { format(["shading": $0.map { (try? JSON(encoding: $0)) ?? .null } ?? .null]) }
            HStack {
                Toggle("Hyphenate", isOn: Binding(get: { shared(spans) { $0.hyphenate } ?? false }, set: { format(["hyphenate": .bool($0)]) }))
                Spacer()
                Picker("Language", selection: Binding(
                    get: { shared(spans) { $0.lang } ?? .en },
                    set: { format(["lang": .string($0.rawValue)]) })
                ) {
                    Text("English").tag(Attrs.Lang.en)
                    Text("German").tag(Attrs.Lang.de)
                    Text("French").tag(Attrs.Lang.fr)
                    Text("Italian").tag(Attrs.Lang.it)
                    Text("Spanish").tag(Attrs.Lang.es)
                    Text("Dutch").tag(Attrs.Lang.nl)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

/// The text styles to apply, and making one of the text.
struct StyleMenu: View {
    let editor: Editor
    let spans: [Attrs]
    let format: ([String: JSON]) -> Void

    /// The attributes a text style sets.
    static let styled = [
        "size", "lineHeight", "letterSpacing", "paragraphSpacing", "paragraphIndent", "indentLeft", "indentRight", "spaceBefore", "font",
        "textCase", "textDecoration", "features", "position", "baselineShift", "dropLines", "dropChars", "keepLines", "keepTogether",
        "keepNext", "tabs", "list",
    ]

    /// The styled attributes of `a` as JSON.
    static func own(_ a: Attrs) -> [String: JSON] {
        guard let all = (try? JSON(encoding: a))?.object else { return [:] }
        return all.filter { styled.contains($0.key) }
    }

    var body: some View {
        let styles = editor.snapshot.textStyles
        let style = shared(spans) { $0.textStyle }
        let current = styles.first { $0.id == style }
        Menu {
            Button("No Style") { format(["textStyle": ""]) }
            Divider()
            ForEach(styles) { s in
                Button(s.name) { format(["textStyle": .string(s.id)]) }
            }
            if let current, let first = spans.first {
                Divider()
                Button("Reset to Style") { format(["textStyle": .string(current.id)]) }
                Button("Update Style") { editor.apply(.setTextStyle(current.id, Self.own(first).filter { current.bindings[$0.key] == nil })) }
            }
            Divider()
            Button("New Style from Text") {
                guard let first = spans.first else { return }
                let names = Set(styles.map(\.name))
                var i = 1
                while names.contains(String(localized: "Text style \(i)")) { i += 1 }
                if let id = editor.apply(.addTextStyle(name: String(localized: "Text style \(i)"), Self.own(first))).first {
                    format(["textStyle": .string(id)])
                }
            }
            .disabled(spans.isEmpty)
        } label: {
            Text(style == nil ? String(localized: "Mixed") : current?.name ?? String(localized: "No Style"))
        }
        .help("Text style")
    }
}

/// The fonts of the document, then those of this Mac, which the document takes in when picked.
struct FontMenu: View {
    let editor: Editor
    /// The font, nil for the bundled one.
    let value: Typeface?
    var mixed = false
    let set: (Typeface?) -> Void
    @State private var open = false
    @State private var query = ""

    private var bundled: Typeface? { editor.snapshot.fonts.first }

    var body: some View {
        Button {
            open = true
        } label: {
            HStack {
                Text(mixed ? String(localized: "Mixed") : (value ?? bundled)?.name ?? "")
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
        }
        .help("Font")
        .popover(isPresented: $open, arrowEdge: .leading) {
            FontList(editor: editor, value: value, query: $query) { face in
                set(face)
                open = false
            }
            .frame(width: 280, height: 380)
        }
        .accessibilityIdentifier("font-menu")
    }
}

private struct FontList: View {
    let editor: Editor
    let value: Typeface?
    @Binding var query: String
    let pick: (Typeface?) -> Void
    @State private var families: [(family: String, faces: [(postscript: String, style: String)])] = []

    var body: some View {
        let fonts = editor.snapshot.fonts
        let q = query.lowercased()
        VStack(spacing: 0) {
            TextField("Search fonts", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List {
                Section("In this document") {
                    ForEach(Array(fonts.enumerated()), id: \.element.hash) { i, f in
                        if q.isEmpty || f.name.lowercased().contains(q) {
                            Button {
                                pick(i == 0 ? nil : f)
                            } label: {
                                Label(f.name, systemImage: (value ?? fonts.first) == f ? "checkmark" : "")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(editor.snapshot.missingFonts, id: \.font.hash) { m in
                        Label(m.font.name, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                            .help("Missing: its text is set in the bundled font")
                    }
                }
                Section("On this Mac") {
                    ForEach(families.filter { q.isEmpty || $0.family.lowercased().contains(q) }, id: \.family) { fam in
                        DisclosureGroup(fam.family) {
                            ForEach(fam.faces, id: \.postscript) { face in
                                Button(face.style.isEmpty ? face.postscript : face.style) { add(face.postscript) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .task { if families.isEmpty { families = FontFile.families() } }
    }

    /// Takes the Mac's font `postscript` into the document and sets the text in it.
    private func add(_ postscript: String) {
        let font = CTFontCreateWithName(postscript as CFString, 12, nil)
        guard let data = FontFile.data(of: font) else {
            editor.fail(String(localized: "This font cannot be used"))
            return
        }
        if let face = editor.addFont(data) { pick(face) }
    }
}

/// Characters keyboards lack, and the page number, inserted into the edited text.
struct CharacterMenu: View {
    let editor: Editor
    let node: Node?

    static let characters: [(LocalizedStringKey, String)] = [
        ("Em dash", "\u{2014}"), ("En dash", "\u{2013}"), ("Ellipsis", "\u{2026}"), ("Bullet", "\u{2022}"),
        ("Non-breaking space", "\u{00a0}"), ("Thin space", "\u{2009}"), ("Low quote", "\u{201e}"), ("Left quote", "\u{201c}"),
        ("Right quote", "\u{201d}"), ("Apostrophe", "\u{2019}"), ("Right guillemet", "\u{00bb}"), ("Left guillemet", "\u{00ab}"),
        ("Copyright", "\u{00a9}"), ("Registered", "\u{00ae}"), ("Trademark", "\u{2122}"), ("Section", "\u{00a7}"),
        ("Degree", "\u{00b0}"), ("Multiplication", "\u{00d7}"),
    ]

    var body: some View {
        Menu {
            Button("Page Number") { put(TextEdit.pageNumber) }
            Divider()
            ForEach(Self.characters, id: \.1) { title, c in
                Button { put(c) } label: { Text(title) + Text(verbatim: "  \(c)") }
            }
            Divider()
            Button("Emoji & Symbols") { NSApp.orderFrontCharacterPalette(nil) }
        } label: {
            Image(systemName: "character")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Insert character")
        .disabled(node?.kind != .text)
    }

    private func put(_ c: String) {
        guard let node, node.kind == .text else { return }
        if editor.editing?.id != node.id {
            let end = editor.story(of: node)?.utf16Length ?? 0
            editor.edit(node.id, anchor: end, focus: end)
        }
        editor.insert(c)
    }
}

/// Case, decoration, indents, lists, drop caps and OpenType features.
struct TypeOptions: View {
    let spans: [Attrs]
    let set: ([String: JSON]) -> Void
    @State private var open = false

    private func number(_ key: String) -> (Double) -> Void { { set([key: .number($0)]) } }

    /// OpenType features: tag, title and whether fonts apply it unless turned off.
    static let features: [(String, LocalizedStringKey, Bool)] = [
        ("kern", "Kerning", true), ("liga", "Ligatures", true), ("dlig", "Discretionary ligatures", false),
        ("smcp", "Small caps", false), ("c2sc", "Capitals to small caps", false), ("case", "Case-sensitive forms", false),
        ("frac", "Fractions", false), ("zero", "Slashed zero", false), ("sups", "Superscript glyphs", false),
        ("subs", "Subscript glyphs", false), ("ordn", "Ordinals", false),
    ]

    private func on(_ tag: String, _ byDefault: Bool) -> Bool? {
        shared(spans) { byDefault ? !$0.features.contains("\(tag)=0") : $0.features.contains(tag) }
    }

    /// The features with `drop` taken out and `add` put in.
    private func put(drop: [String], add: [String]) {
        let kept = (spans.first?.features ?? []).filter { f in !drop.contains { f == $0 || f == "\($0)=0" } }
        set(["features": .array((kept + add).sorted().map { .string($0) })])
    }

    var body: some View {
        Button { open = true } label: { Image(systemName: "ellipsis.circle") }
            .buttonStyle(.borderless)
            .help("Type options")
            .popover(isPresented: $open, arrowEdge: .leading) {
                Form {
                    Section("Character") {
                        picker("Case", \.textCase, [(.original, "As typed"), (.upper, "Upper case"), (.lower, "Lower case"), (.title, "Title case")])
                        picker("Decoration", \.textDecoration, [(.none, "None"), (.underline, "Underline"), (.strikethrough, "Strikethrough")])
                        picker("Position", \.position, [(.normal, "Normal"), (.superscript, "Superscript"), (.subscript, "Subscript")])
                        NumberField(label: "Shift", help: "Baseline shift", value: shared(spans) { $0.baselineShift }, unit: .points, commit: number("baselineShift"))
                    }
                    Section("Indents & Spacing") {
                        NumberField(label: "First line", value: shared(spans) { $0.paragraphIndent }, unit: .points, commit: number("paragraphIndent"))
                        NumberField(label: "Left", value: shared(spans) { $0.indentLeft }, unit: .points, commit: number("indentLeft"))
                        NumberField(label: "Right", value: shared(spans) { $0.indentRight }, unit: .points, commit: number("indentRight"))
                        NumberField(label: "Before", value: shared(spans) { $0.spaceBefore }, unit: .points, commit: number("spaceBefore"))
                    }
                    Section("Paragraph") {
                        picker("List", \.list, [(.none, "None"), (.bullet, "Bullets"), (.number, "Numbers")])
                        NumberField(label: "Keep lines", value: shared(spans) { Double($0.keepLines) }, unit: .plain, integer: true, range: 1 ... 20, commit: number("keepLines"))
                        toggle("Keep lines together", \.keepTogether, "keepTogether")
                        toggle("Keep with next", \.keepNext, "keepNext")
                        NumberField(label: "Drop lines", help: "Drop cap lines", value: shared(spans) { Double($0.dropLines) }, unit: .plain, integer: true, range: 0 ... 20, commit: number("dropLines"))
                        NumberField(label: "Drop chars", help: "Drop cap characters", value: shared(spans) { Double($0.dropChars) }, unit: .plain, integer: true, range: 1 ... 20, commit: number("dropChars"))
                    }
                    Section("OpenType") {
                        figures("Figures", [("lnum", "Lining"), ("onum", "Oldstyle")])
                        figures("Figure spacing", [("pnum", "Proportional"), ("tnum", "Tabular")])
                        ForEach(Self.features, id: \.0) { tag, title, byDefault in
                            Toggle(title, isOn: Binding(
                                get: { on(tag, byDefault) ?? false },
                                set: { put(drop: [tag], add: byDefault ? ($0 ? [] : ["\(tag)=0"]) : ($0 ? [tag] : [])) }))
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(width: 300, height: 520)
            }
    }

    private func picker<T: RawRepresentable & Hashable>(_ title: LocalizedStringKey, _ key: KeyPath<Attrs, T>, _ options: [(T, LocalizedStringKey)]) -> some View where T.RawValue == String {
        Picker(title, selection: Binding(
            get: { shared(spans) { $0[keyPath: key] } ?? options[0].0 },
            set: { v in set([Self.name(key): .string(v.rawValue)]) })
        ) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
    }

    private func toggle(_ title: LocalizedStringKey, _ key: KeyPath<Attrs, Bool>, _ name: String) -> some View {
        Toggle(title, isOn: Binding(get: { shared(spans) { $0[keyPath: key] } ?? false }, set: { set([name: .bool($0)]) }))
    }

    private func figures(_ title: LocalizedStringKey, _ tags: [(String, LocalizedStringKey)]) -> some View {
        Picker(title, selection: Binding(
            get: { shared(spans) { a in tags.first { a.features.contains($0.0) }?.0 ?? "" } ?? "" },
            set: { put(drop: tags.map(\.0), add: $0.isEmpty ? [] : [$0]) })
        ) {
            Text("Default").tag("")
            ForEach(tags, id: \.0) { Text($0.1).tag($0.0) }
        }
    }

    private static func name(_ key: PartialKeyPath<Attrs>) -> String {
        switch key {
        case \Attrs.textCase: "textCase"
        case \Attrs.textDecoration: "textDecoration"
        case \Attrs.position: "position"
        case \Attrs.list: "list"
        default: ""
        }
    }
}

/// Resizing, insets, columns, vertical alignment and baseline grid of a text frame.
struct TextFrameSection: View {
    let editor: Editor
    let node: Node

    private func set(_ props: [String: JSON]) { editor.apply(.set(id: node.id, props)) }
    private func number(_ key: String) -> (Double) -> Void { { set([key: .number($0)]) } }

    var body: some View {
        Section("Text Frame") {
            Picker("Resizing", selection: Binding(
                get: { node.sizing.resizing },
                set: { mode in if let s = try? JSON(encoding: node.sizing.text(mode)) { set(["sizing": s]) } })
            ) {
                Text("Auto Width").tag(Sizing.Resizing.autoWidth)
                    .disabled(node.prev != nil || node.next != nil)
                Text("Auto Height").tag(Sizing.Resizing.autoHeight)
                    .disabled(node.next != nil)
                Text("Fixed").tag(Sizing.Resizing.fixedSize)
            }
            .pickerStyle(.segmented)
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    NumberField(label: "↑", help: "Top inset", value: node.insetTop, range: 0 ... .infinity, commit: number("insetTop"))
                    NumberField(label: "→", help: "Right inset", value: node.insetRight, range: 0 ... .infinity, commit: number("insetRight"))
                }
                GridRow {
                    NumberField(label: "↓", help: "Bottom inset", value: node.insetBottom, range: 0 ... .infinity, commit: number("insetBottom"))
                    NumberField(label: "←", help: "Left inset", value: node.insetLeft, range: 0 ... .infinity, commit: number("insetLeft"))
                }
                GridRow {
                    NumberField(label: "Columns", value: node.columns.map(Double.init), unit: .plain, integer: true, range: 1 ... 20, commit: number("columns"))
                    NumberField(label: "Gutter", value: node.gutter, range: 0 ... .infinity, commit: number("gutter"))
                }
                GridRow {
                    NumberField(label: "Baseline", help: "Baseline grid", value: node.baselineGrid, unit: .points, range: 0 ... 1000, zero: "–", commit: number("baselineGrid"))
                    NumberField(label: "Start", help: "Baseline grid start", value: node.baselineStart, unit: .points, range: 0 ... 1000, commit: number("baselineStart"))
                }
                GridRow {
                    NumberField(label: "Min", help: "Min height", value: node.minHeight, range: 0 ... .infinity, zero: "–", commit: number("minHeight"))
                    NumberField(label: "Lines", help: "Max lines", value: node.maxLines.map(Double.init), unit: .plain, integer: true, range: 0 ... 1000, zero: "–", commit: number("maxLines"))
                }
            }
            Picker("Vertical align", selection: Binding(get: { node.verticalAlign ?? .top }, set: { set(["verticalAlign": .string($0.rawValue)]) })) {
                Label("Top", systemImage: "align.vertical.top").labelStyle(.iconOnly).tag(VerticalAlign.top)
                Label("Center", systemImage: "align.vertical.center").labelStyle(.iconOnly).tag(VerticalAlign.center)
                Label("Bottom", systemImage: "align.vertical.bottom").labelStyle(.iconOnly).tag(VerticalAlign.bottom)
            }
            .pickerStyle(.segmented)
            Toggle("Trim to cap height", isOn: Binding(get: { node.trim ?? false }, set: { set(["trim": .bool($0)]) }))
            if (node.columns ?? 1) > 1 {
                let rule = node.columnRule.flatMap { $0.weight > 0 ? $0 : nil }
                HStack {
                    ColorCheck(editor: editor, label: "Column rule", color: .some(rule?.color), modes: node.activeModes) { c in
                        if let c {
                            set(["columnRule": ["weight": .number(rule?.weight ?? 1), "color": (try? JSON(encoding: c)) ?? .null]])
                        } else if let rule {
                            set(["columnRule": ["weight": 0, "color": (try? JSON(encoding: rule.color)) ?? .null]])
                        }
                    }
                    if let rule {
                        NumberField(label: "Weight", help: "Column rule weight", value: rule.weight, unit: .points, range: 0...100) {
                            set(["columnRule": ["weight": .number($0), "color": (try? JSON(encoding: rule.color)) ?? .null]])
                        }
                    }
                }
            }
        }
    }
}

/// A check that turns a colour on or off, and its well while it is on; nil is mixed.
struct ColorCheck: View {
    let editor: Editor
    let label: LocalizedStringKey
    /// Nil when mixed, .some(nil) when off.
    let color: SatzCore.Color??
    var modes: Modes = [:]
    let set: (SatzCore.Color?) -> Void

    var body: some View {
        HStack {
            Toggle(label, isOn: Binding(
                get: { (color ?? nil) != nil },
                set: { set($0 ? ColorMath.neutral("gray", editor.snapshot.colorMode) : nil) }))
            if let c = color ?? nil {
                ColorWell(label: label, color: c, mode: editor.snapshot.colorMode, scope: Scope(editor.snapshot, modes: modes), editor: editor) { set($0) }
            }
        }
    }
}

/// The document's text styles, each with its font and size.
struct TextStylesSection: View {
    let editor: Editor

    var body: some View {
        let styles = editor.snapshot.textStyles
        if !styles.isEmpty {
            Section("Text Styles") {
                ForEach(styles) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Name", text: Binding(get: { s.name }, set: { editor.apply(.setTextStyle(s.id, name: $0)) }))
                                .textFieldStyle(.plain)
                                .font(.headline)
                            TypeOptions(spans: [s.attrs]) { editor.apply(.setTextStyle(s.id, $0)) }
                            Button { editor.apply(.deleteTextStyle(s.id)) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help("Delete text style")
                        }
                        FontMenu(editor: editor, value: s.attrs.font) { face in
                            editor.apply(.setTextStyle(s.id, ["font": (try? JSON(encoding: face)) ?? .null]))
                        }
                        HStack {
                            NumberField(label: "Size", value: s.attrs.size, unit: .points, range: 0.1 ... 5000) { editor.apply(.setTextStyle(s.id, ["size": .number($0)])) }
                            NumberField(label: "Line", value: s.attrs.lineHeight, unit: .points, range: 0 ... 5000, zero: String(localized: "Auto")) {
                                editor.apply(.setTextStyle(s.id, ["lineHeight": .number($0)]))
                            }
                        }
                    }
                }
            }
        }
    }
}
