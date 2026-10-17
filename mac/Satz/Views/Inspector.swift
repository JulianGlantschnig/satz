import SatzCore
import SwiftUI

/// The right panel: the selection's layout, or the document and page without one.
struct Inspector: View {
    let editor: Editor

    var body: some View {
        if editor.showsPreflight {
            Preflight(editor: editor)
        } else {
            properties
        }
    }

    private var properties: some View {
        let nodes = editor.selected
        return Form {
            if nodes.isEmpty || editor.showsOverview {
                DocumentSection(editor: editor)
                PageSection(editor: editor)
                SwatchesSection(editor: editor)
                VariablesSection(editor: editor)
                TextStylesSection(editor: editor)
            } else {
                SelectionHeader(editor: editor, nodes: nodes)
                if editor.editing == nil {
                    if let image = editor.selectedImage { ImageSection(editor: editor, node: image) }
                    ArrangeSection(editor: editor, nodes: nodes)
                    LayoutSection(editor: editor, nodes: nodes)
                    if nodes.count == 1, ResizingSection.applies(editor, nodes[0]) { ResizingSection(editor: editor, node: nodes[0]) }
                    if nodes.count == 1, nodes[0].kind == .frame { AutoLayoutSection(editor: editor, node: nodes[0]) }
                }
                if nodes.allSatisfy({ $0.kind == .text }) {
                    TextSection(editor: editor, nodes: nodes)
                    if nodes.count == 1, editor.editing == nil { TextFrameSection(editor: editor, node: nodes[0]) }
                }
                if editor.editing == nil {
                    PaintSections(editor: editor, nodes: nodes)
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("inspector")
    }
}

/// The value of `get` for all of `nodes`, or nil when they differ.
func same<Item, T: Equatable>(_ nodes: [Item], _ get: (Item) -> T) -> T? {
    guard let first = nodes.first.map(get) else { return nil }
    return nodes.dropFirst().allSatisfy { get($0) == first } ? first : nil
}

private struct SelectionHeader: View {
    let editor: Editor
    let nodes: [Node]

    var body: some View {
        Section {
            HStack {
                Text(nodes.count == 1 ? (nodes[0].kind == .text ? String(localized: "Text frame") : nodes[0].name) : String(localized: "\(nodes.count) layers"))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if nodes.count == 1, nodes[0].overrideOf != nil {
                    Button("Reset to Master") { editor.apply(.resetToMaster([nodes[0].id])) }
                        .controlSize(.small)
                }
            }
        }
    }
}

private struct ArrangeSection: View {
    let editor: Editor
    let nodes: [Node]

    var body: some View {
        Section {
            HStack(spacing: 2) {
                ForEach(Editor.Align.allCases.prefix(6)) { a in icon(a) }
            }
            HStack(spacing: 2) {
                ForEach(Editor.Align.allCases.suffix(3)) { a in icon(a).disabled(a == .tidy ? nodes.count < 2 : nodes.count < 3) }
                Divider().frame(height: 16)
                Button { editor.flip(vertical: false) } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .help("Flip Horizontal")
                Button { editor.flip(vertical: true) } label: { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
                    .help("Flip Vertical")
            }
            if let row = editor.row {
                NumberField(
                    label: row.axis == .x ? "↔" : "↕", help: row.axis == .x ? "Horizontal spacing" : "Vertical spacing",
                    value: row.gaps.allSatisfy { abs($0 - row.gaps[0]) < 1e-6 } ? row.gaps[0] : nil
                ) { editor.setGap(row, $0) }
            }
            if editor.combinable {
                HStack(spacing: 2) {
                    ForEach(BooleanOp.allCases, id: \.self) { op in
                        Button { editor.combine(op) } label: { Image(systemName: Self.symbol(op)) }
                            .help(Self.title(op))
                    }
                }
            }
        }
        .buttonStyle(.borderless)
    }

    private func icon(_ a: Editor.Align) -> some View {
        Button { editor.align(a) } label: { Image(systemName: a.symbol).frame(width: 22, height: 18) }
            .help(Text(a.title))
    }

    static func symbol(_ op: BooleanOp) -> String {
        switch op {
        case .union: "square.on.square.squareshape.controlhandles"
        case .subtract: "square.slash"
        case .intersect: "square.on.square.intersection.dashed"
        case .exclude: "square.on.square.dashed"
        }
    }

    static func title(_ op: BooleanOp) -> LocalizedStringKey {
        switch op {
        case .union: "Union"
        case .subtract: "Subtract"
        case .intersect: "Intersect"
        case .exclude: "Exclude"
        }
    }
}

private struct LayoutSection: View {
    let editor: Editor
    let nodes: [Node]

    /// The rotation of `n`, for a group that of all its layers, or nil if they differ.
    static func turnOf(_ n: Node) -> Double? {
        guard n.kind == .group else { return n.rotation }
        let turns = (n.children ?? []).map(turnOf)
        return turns.allSatisfy { $0 != nil && $0 == turns.first! } ? turns.first ?? 0 : nil
    }

    private func frame(_ key: String) -> (Double) -> Void {
        { v in
            editor.batch {
                for n in nodes {
                    let by = n.keepRatio && (key == "w" || key == "h") ? (key == "w" ? (n.w != 0 ? v / n.w : 1) : (n.h != 0 ? v / n.h : 1)) : 1
                    var (x, y, w, h) = (n.x, n.y, n.w * by, n.h * by)
                    switch key {
                    case "x": x = v
                    case "y": y = v
                    case "w": w = v
                    default: h = v
                    }
                    editor.apply(.setFrame(id: n.id, x: x, y: y, w: w, h: h))
                }
            }
        }
    }

    private func set(_ props: [String: JSON]) {
        editor.batch {
            for n in nodes { editor.apply(.set(id: n.id, props)) }
        }
    }

    /// `field` with a variable menu when one layer is selected; lengths bind in mm.
    @ViewBuilder
    private func bindable(_ prop: String, _ title: LocalizedStringKey, _ pt: Double?, @ViewBuilder field: @escaping () -> some View) -> some View {
        if nodes.count == 1 {
            VariableBinding(editor: editor, id: nodes[0].id, prop: prop, title: title, value: pt.map { $0 / Units.ptPerMM }, field: field)
        } else {
            field()
        }
    }

    var body: some View {
        let one = nodes.count == 1 ? nodes[0] : nil
        let line = one.flatMap(Editor.ends)
        Section {
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    NumberField(label: "X", value: nodes.count > 1 ? same(nodes) { $0.x } : one?.x, commit: frame("x"))
                    NumberField(label: "Y", value: nodes.count > 1 ? same(nodes) { $0.y } : one?.y, commit: frame("y"))
                }
                if let (a, b) = line, let one {
                    let length = hypot(b.x - a.x, b.y - a.y)
                    let angle = atan2(a.y - b.y, b.x - a.x) * 180 / .pi
                    GridRow {
                        NumberField(label: "L", help: "Length", value: length) { setLine(one, a, $0, angle) }
                        NumberField(label: "∠", help: "Angle", value: angle, unit: .degrees) { setLine(one, a, length, $0) }
                    }
                } else {
                    GridRow {
                        bindable("w", "W", same(nodes) { $0.w }) {
                            NumberField(label: "W", value: same(nodes) { $0.w }, range: 0 ... .infinity, commit: frame("w"))
                        }
                        bindable("h", "H", same(nodes) { $0.h }) {
                            NumberField(label: "H", value: same(nodes) { $0.h }, range: 0 ... .infinity, commit: frame("h"))
                        }
                    }
                    GridRow {
                        NumberField(label: "∠", help: "Rotation", value: same(nodes) { Self.turnOf($0) } ?? nil, unit: .degrees) { v in
                            editor.batch {
                                for n in nodes {
                                    if n.kind != .group {
                                        editor.apply(.set(id: n.id, ["rotation": .number((v.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360))]))
                                    } else {
                                        let b = editor.shown(n)
                                        editor.turn([n], by: v - (Self.turnOf(n) ?? 0), around: b.center)
                                    }
                                }
                            }
                        }
                        if nodes.allSatisfy(\.isRounded) {
                            NumberField(label: "R", help: "Corner radius", value: same(nodes) { n in
                                let r = n.radii
                                return r.allSatisfy { $0 == r[0] } ? r[0] : -1
                            }.flatMap { $0 < 0 ? nil : $0 }, range: 0 ... .infinity) { set(["radius": .number($0), "corners": .array([])]) }
                        }
                    }
                }
            }
            if line == nil {
                Toggle("Keep aspect ratio", isOn: Binding(
                    get: { same(nodes) { $0.keepRatio } ?? false },
                    set: { set(["keepRatio": .bool($0)]) }))
            }
            if let one, one.kind == .frame {
                Toggle("Clip content", isOn: Binding(get: { one.clip ?? false }, set: { set(["clip": .bool($0)]) }))
            }
        } header: {
            Text("Layout")
        }
    }

    private func setLine(_ n: Node, _ a: CGPoint, _ length: Double, _ degrees: Double) {
        let r = degrees * .pi / 180
        editor.apply(.setPath(id: n.id, path: [0, a.x, a.y, 1, a.x + length * cos(r), a.y - length * sin(r)]))
    }
}
